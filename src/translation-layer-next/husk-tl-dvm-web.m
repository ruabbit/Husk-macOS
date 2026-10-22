/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * android.webkit.WebView for Java apps (husk.Web's natives), on WKWebView.
 *
 * Each WebView in the app's view tree is a WKWebView in a container under the app's screen: the view tree leaves a clear hole where
 * the WebView sits (as SurfaceView does), the screen's layer stops being opaque while any web view shows, and touches that land in
 * a web view's frame go through to it. Every call from Java is queued onto the main thread; everything WebKit reports comes back as
 * an event string ("kind \x1f id \x1f fields...") that Java polls (input phase 9) and hands to the WebView's clients.
 *
 * What WebKit cannot do itself goes through Java, asynchronously, by call ids that Java answers with Web.reply / Web.respond:
 *  - shouldOverrideUrlLoading: the navigation waits on its decision handler;
 *  - alert / confirm / prompt, and the addJavascriptInterface bridge (a prompt() whose message starts "husk:"), wait on the panel's
 *    completion handler, so a bridged call is synchronous for the page as on Android;
 *  - the app's own content (file:///android_asset, and http(s) origins the app serves from shouldInterceptRequest, as Capacitor
 *    does) loads as huskapp://<host>/<path>: Java maps those URLs, asks the app, and answers with the bytes, or with the real URL
 *    for the host to fetch.
 */
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/CAMetalLayer.h>
#include <TargetConditionals.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
typedef UIView HView;
#else
#import <AppKit/AppKit.h>
typedef NSView HView;
#endif

#include "husk-tl-dvm-internal.h"
#include "husk-tl-dvm-javaapp.h"
#import "husk-tl-dvm-web-host.h"

void tl_log_line(const char *fmt, ...);

#define NAT(fn) static bool fn(jobj *self, const jvalue *a, jvalue *ret)
static jvalue L(jobj *o) { jvalue r; r.l = o; return r; }
static jvalue Z(bool b) { jvalue r; r.j = 0; r.z = b; return r; }

/* ---- events for Java */

static pthread_mutex_t g_ev_lock = PTHREAD_MUTEX_INITIALIZER;
static char **g_ev;
static int g_nev, g_cev;

static void emit(NSString *kind, int wid, NSArray<NSString *> *fields)
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@\x1f%d", kind, wid];
    for (NSString *f in fields) [s appendFormat:@"\x1f%@", f ?: @""];
    const char *u = s.UTF8String;
    pthread_mutex_lock(&g_ev_lock);
    if (g_nev == g_cev) { g_cev = g_cev ? g_cev * 2 : 32; g_ev = realloc(g_ev, (size_t)g_cev * sizeof(*g_ev)); }
    g_ev[g_nev++] = strdup(u ? u : "");
    pthread_mutex_unlock(&g_ev_lock);
    tl_javaapp_touch(9, 0, 0, 0);
}

/* ---- the host's screen and the container the web views live in */

static __weak HView *g_screen;    /* the app's GL view */
static HView *g_container;
static float g_scale = 1;         /* surface pixels per point */
static pthread_mutex_t g_hit_lock = PTHREAD_MUTEX_INITIALIZER;
typedef struct { int id; bool visible, touchable; float x, y, w, h; } hit_rect;   /* points */
static hit_rect g_hits[16];
static int g_nhits;

#if !TARGET_OS_IPHONE
@interface HuskFlippedView : NSView
@end
@implementation HuskFlippedView
- (BOOL)isFlipped { return YES; }
@end
static NSWindow *g_window;
#endif

static void ensure_container(void)
{
    if (g_container) return;
#if TARGET_OS_IPHONE
    tl_log_line("web: the host has given no container for web views");      /* husk_java_web_attach comes before the app starts */
#else
    /* the harness: an off-screen window the size of the app's surface. WebKit only renders a page whose window is on screen:
       this one shows one column of pixels at the screen's right edge */
    CGFloat w = g_screen ? g_screen.frame.size.width : 400, h = g_screen ? g_screen.frame.size.height : 800;
    NSRect scr = NSScreen.mainScreen ? NSScreen.mainScreen.frame : NSMakeRect(0, 0, 1440, 900);
    g_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(NSMaxX(scr) - 1, NSMinY(scr), w, h) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    g_window.ignoresMouseEvents = YES;
    g_window.level = NSFloatingWindowLevel;
    g_container = [[HuskFlippedView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    g_window.contentView = g_container;
    [g_window orderFrontRegardless];
#endif
}

static void set_screen_opaque(bool opaque)
{
#if TARGET_OS_IPHONE
    if (!g_screen) return;
    g_screen.opaque = opaque;
    g_screen.backgroundColor = opaque ? UIColor.blackColor : UIColor.clearColor;
    g_screen.layer.opaque = opaque;
    for (CALayer *l in g_screen.layer.sublayers) l.opaque = opaque;
#else
    if (!g_screen) return;
    g_screen.layer.backgroundColor = (opaque ? NSColor.blackColor : NSColor.clearColor).CGColor;
    g_screen.layer.opaque = opaque;
    for (CALayer *layer in g_screen.layer.sublayers) {
        if ([layer isKindOfClass:CAMetalLayer.class]) layer.opaque = opaque;
        for (CALayer *child in layer.sublayers)
            if ([child isKindOfClass:CAMetalLayer.class]) child.opaque = opaque;
    }
#endif
}

/* ---- one web view */

@class HuskWeb;
@interface HuskWebPending : NSObject
@property int wid;
@property char kind;
@property id value;
@property NSURLSessionDataTask *network;
@end
@implementation HuskWebPending
@end
static NSMutableDictionary<NSNumber *, HuskWeb *> *g_views;
static NSMutableDictionary<NSNumber *, HuskWeb *> *g_retiring;
static NSMutableDictionary<NSNumber *, HuskWebPending *> *g_pending;
static int g_next_call = 1;
static atomic_int g_visible_webs;
static NSUUID *g_host_store;
static BOOL g_host_preparing, g_host_prepared, g_host_closing, g_detach_failed;
static dispatch_group_t g_detaching;

static void cancel_pending_except_bridge(int wid, BOOL preserveBridge)
{
    for (NSNumber *key in g_pending.allKeys) {
        HuskWebPending *p = g_pending[key];
        if (wid && p.wid != wid) continue;
        if (preserveBridge && p.kind == 'j') continue;
        [g_pending removeObjectForKey:key];
        [p.network cancel];
        switch (p.kind) {
        case 'o': ((void (^)(WKNavigationActionPolicy))p.value)(WKNavigationActionPolicyCancel); break;
        case 'A': ((void (^)(void))p.value)(); break;
        case 'C': ((void (^)(BOOL))p.value)(NO); break;
        case 'j': if (g_host_store) g_detach_failed = YES; // accepted plugin work was abandoned
        case 'P': ((void (^)(NSString *))p.value)(nil); break;
        case 'r': [(id<WKURLSchemeTask>)p.value didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]]; break;
        }
    }
}
static void cancel_pending(int wid) { cancel_pending_except_bridge(wid, NO); }
static dispatch_group_t cookie_writes(void)
{
    static dispatch_group_t group;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ group = dispatch_group_create(); });
    return group;
}
static dispatch_group_t network_requests(void)
{
    static dispatch_group_t group;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ group = dispatch_group_create(); });
    return group;
}

/* ---- each Android app's own website data (cookies, storage), as Android keeps a WebView data directory per app: a data store of
 * its own where the system has them (iOS 17, macOS 14), the shared one before that. CookieManager reads and writes its cookies. */
static NSString *g_app;                                     /* the package, from husk.Web.app */
static WKWebsiteDataStore *g_store;
static NSArray<NSHTTPCookie *> *g_cookies;                  /* the store's cookies, kept current for CookieManager's synchronous reads */
static pthread_mutex_t g_cookie_lock = PTHREAD_MUTEX_INITIALIZER;

static WKWebsiteDataStore *data_store(void)
{
    if (g_store) return g_store;
    if (@available(iOS 17.0, macOS 14.0, *)) {
        if (g_host_store) g_store = [WKWebsiteDataStore dataStoreForIdentifier:g_host_store];
        else if (g_app.length) {
            /* a fixed identifier per package: the first 16 bytes of its name's hash, shaped as a UUID */
            uint8_t b[16] = { 0 };
            const char *u = g_app.UTF8String;
            uint64_t h1 = 1469598103934665603ull, h2 = 1099511628211ull ^ 0x9e3779b97f4a7c15ull;
            for (const char *q = u; *q; q++) { h1 = (h1 ^ (uint8_t)*q) * 1099511628211ull; h2 = (h2 ^ (uint8_t)*q) * 0x100000001b3ull + 7; }
            memcpy(b, &h1, 8); memcpy(b + 8, &h2, 8);
            b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
            g_store = [WKWebsiteDataStore dataStoreForIdentifier:[[NSUUID alloc] initWithUUIDBytes:b]];
        }
    }
    if (!g_store) g_store = [WKWebsiteDataStore defaultDataStore];
    return g_store;
}

@interface HuskCookieWatch : NSObject <WKHTTPCookieStoreObserver>
@end
@implementation HuskCookieWatch
- (void)cookiesDidChangeInCookieStore:(WKHTTPCookieStore *)store
{
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *all) {
        pthread_mutex_lock(&g_cookie_lock); g_cookies = [all copy]; pthread_mutex_unlock(&g_cookie_lock);
    }];
}
@end
static HuskCookieWatch *g_cookie_watch;
/* on the main thread: watching the store, and a first reading of it */
static void cookies_watch(void)
{
    if (g_cookie_watch) return;
    g_cookie_watch = [HuskCookieWatch new];
    WKHTTPCookieStore *cs = data_store().httpCookieStore;
    [cs addObserver:g_cookie_watch];
    [g_cookie_watch cookiesDidChangeInCookieStore:cs];
}
static bool cookie_matches(NSHTTPCookie *c, NSURL *url)
{
    NSString *host = url.host.lowercaseString ?: @"", *d = c.domain.lowercaseString ?: @"";
    if ([d hasPrefix:@"."]) { NSString *bare = [d substringFromIndex:1]; if (![host isEqualToString:bare] && ![host hasSuffix:d]) return false; }
    else if (![host isEqualToString:d]) return false;
    NSString *path = url.path.length ? url.path : @"/", *cp = c.path.length ? c.path : @"/";
    if (![path hasPrefix:cp]) return false;
    if (c.isSecure && ![url.scheme.lowercaseString isEqualToString:@"https"]) return false;
    if (c.expiresDate && c.expiresDate.timeIntervalSinceNow < 0) return false;
    return true;
}
/* "a=1; b=2" for a URL, or nil */
static NSString *cookie_header(NSURL *url)
{
    if (!url) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    pthread_mutex_lock(&g_cookie_lock);
    for (NSHTTPCookie *c in g_cookies) if (cookie_matches(c, url)) [parts addObject:[NSString stringWithFormat:@"%@=%@", c.name, c.value]];
    pthread_mutex_unlock(&g_cookie_lock);
    return parts.count ? [parts componentsJoinedByString:@"; "] : nil;
}
/* cookies into the store, and into the cache at once (a read right after a write sees it) */
static void cookies_put(NSArray<NSHTTPCookie *> *cs)
{
    if (!cs.count) return;
    pthread_mutex_lock(&g_cookie_lock);
    NSMutableArray *all = [NSMutableArray arrayWithArray:g_cookies ?: @[]];
    for (NSHTTPCookie *c in cs) {
        for (NSInteger i = (NSInteger)all.count - 1; i >= 0; i--) {
            NSHTTPCookie *o = all[(NSUInteger)i];
            if ([o.name isEqualToString:c.name] && [o.domain isEqualToString:c.domain] && [o.path isEqualToString:c.path]) [all removeObjectAtIndex:(NSUInteger)i];
        }
        if (!c.expiresDate || c.expiresDate.timeIntervalSinceNow > 0) [all addObject:c];
    }
    g_cookies = all;
    pthread_mutex_unlock(&g_cookie_lock);
    for (NSHTTPCookie *c in cs) {
        dispatch_group_enter(cookie_writes());
        dispatch_async(dispatch_get_main_queue(), ^{
            [data_store().httpCookieStore setCookie:c completionHandler:^{ dispatch_group_leave(cookie_writes()); }];
        });
    }
}

/* Installed before application scripts. The early capture gate lets the
 * controlled save phase deliver each lifecycle event once, then suppresses
 * WebKit's later unload delivery after Android has gone away. It is enabled
 * only for an independent host that explicitly calls prepare-for-close. */
static NSString *save_stage_js(void)
{
    return @"(()=>{let preparing=false,sealed=false,expected=null,failed=false;"
        "const timeout=setTimeout.bind(window),interval=setInterval.bind(window),raf=requestAnimationFrame.bind(window);"
        "const ct=clearTimeout.bind(window),ci=clearInterval.bind(window),cr=cancelAnimationFrame.bind(window);"
        "const timers=new Set(),intervals=new Set(),frames=new Set();"
        "const bad=()=>{failed=true;window.webkit.messageHandlers.huskConsole.postMessage({saveFailed:true});};"
        "window.setTimeout=(fn,ms,...args)=>{if(sealed)return 0;const id=timeout(()=>{timers.delete(id);if(!sealed){if(typeof fn==='function')fn.apply(window,args);else (0,eval)(String(fn));}},ms);timers.add(id);return id;};"
        "window.clearTimeout=id=>{timers.delete(id);ct(id);};"
        "window.setInterval=(fn,ms,...args)=>{if(preparing)return 0;const id=interval(()=>{if(!preparing){if(typeof fn==='function')fn.apply(window,args);else (0,eval)(String(fn));}},ms);intervals.add(id);return id;};"
        "window.clearInterval=id=>{intervals.delete(id);ci(id);};"
        "window.requestAnimationFrame=fn=>{if(preparing)return 0;const id=raf(t=>{frames.delete(id);if(!preparing)fn(t);});frames.add(id);return id;};"
        "window.cancelAnimationFrame=id=>{frames.delete(id);cr(id);};"
        "['beforeunload','visibilitychange','pagehide','unload'].forEach(type=>window.addEventListener(type,e=>{if(preparing&&e!==expected)e.stopImmediatePropagation();},true));"
        "window.addEventListener('error',()=>{if(preparing&&!sealed)bad();},true);"
        "window.addEventListener('unhandledrejection',()=>{if(preparing&&!sealed)bad();},true);"
        "Object.defineProperty(window,'__huskPrepareClose',{value:async()=>{"
        "if(preparing)throw new Error('Save stage already started');preparing=true;"
        "timers.forEach(ct);intervals.forEach(ci);frames.forEach(cr);timers.clear();intervals.clear();frames.clear();"
        "const waits=[];const send=(target,e)=>{Object.defineProperty(e,'waitUntil',{value:p=>{if(expected!==e)throw new Error('waitUntil outside lifecycle dispatch');waits.push(Promise.resolve(p));}});expected=e;try{target.dispatchEvent(e);}finally{expected=null;}};"
        "try{"
        "Object.defineProperty(document,'hidden',{configurable:true,get:()=>true});Object.defineProperty(document,'visibilityState',{configurable:true,get:()=>'hidden'});"
        "document.getAnimations().forEach(a=>a.pause());"
        "send(window,new Event('beforeunload',{cancelable:true}));send(document,new Event('visibilitychange'));"
        "send(window,new PageTransitionEvent('pagehide',{persisted:false}));send(window,new Event('unload'));"
        "for(let i=0;i<window.frames.length;i++){const f=window.frames[i];if(typeof f.__huskPrepareClose!=='function')throw new Error('Unprepared child frame');waits.push(f.__huskPrepareClose().then(ok=>{if(!ok)throw new Error('Child save failed');}));}"
        "await Promise.all(waits);if(failed)throw new Error('Page save handler failed');return true;"
        "}catch(e){bad();throw e;}finally{sealed=true;window.__huskClosing=true;timers.forEach(ct);timers.clear();}"
        "}});})();";
}

static NSString *bridge_js(void)
{
    /* Android's addJavascriptInterface objects call through prompt(); the console reaches WebChromeClient.onConsoleMessage */
    /* Android's WebView has no speech synthesis: apps put their own (a native TTS plugin) at window.speechSynthesis, which WebKit's
       getter would refuse; it stays WebKit's until they do */
    return @"(function(){if(window.__husk)return;try{Object.defineProperty(window,'speechSynthesis',{value:window.speechSynthesis,writable:true,configurable:true,enumerable:true})}catch(e){}"
            "window.__husk={call:function(o,m,a){if(window.__huskClosing){window.webkit.messageHandlers.huskConsole.postMessage({closing:true});throw new Error('Java runtime is closing');}"
            "var r=prompt('husk:'+JSON.stringify({o:o,m:m,a:Array.prototype.slice.call(a)}));"
            "if(r===null||r===undefined)return undefined;var v=JSON.parse(r);if(v&&v.e)throw new Error(v.e);return v.v;}};"
            "var lv=['log','debug','info','warn','error'];lv.forEach(function(k,i){var o=console[k];console[k]=function(){try{var s=Array.prototype.map.call(arguments,function(x){"
            "try{return x instanceof Error?(x.name+': '+x.message+(x.stack?' | '+String(x.stack).slice(0,600):'')):typeof x==='object'?JSON.stringify(x,function(k,v){return v instanceof Error?{name:v.name,message:v.message,stack:String(v.stack||'').slice(0,600)}:v}):String(x)}catch(e){return String(x)}}).join(' ');"
            "window.webkit.messageHandlers.huskConsole.postMessage({l:i,m:s,s:(document.currentScript&&document.currentScript.src)||location.href});}catch(e){}"
            "if(o)o.apply(console,arguments);};});"
            "window.addEventListener('error',function(e){try{window.webkit.messageHandlers.huskConsole.postMessage({l:4,m:'Uncaught '+e.message+(e.error&&e.error.stack?' | '+String(e.error.stack).slice(0,600):''),s:e.filename||'',n:e.lineno||0});}catch(x){}});})();";
}

@interface HuskWeb : NSObject <WKNavigationDelegate, WKUIDelegate, WKURLSchemeHandler, WKScriptMessageHandler>
@property (nonatomic) int wid;
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic) bool apiLoad;            /* the next navigation is the app's own loadUrl: not offered to shouldOverrideUrlLoading */
@property (nonatomic, strong) NSMutableArray<NSString *> *scripts;
@property (nonatomic) bool edgeLinked;
@property (nonatomic) BOOL closing;
@property (nonatomic) BOOL prepareStarted, prepareFinished, prepareSucceeded;
@property (nonatomic) BOOL waitingForDestroyAck;
@property (nonatomic, copy) void (^prepareCompletion)(BOOL);
@property (nonatomic) WKNavigation *blankNavigation;
@property (nonatomic, copy) void (^closeCompletion)(BOOL);
- (void)closeForHost:(void (^)(BOOL))completion;
- (void)completeClose:(BOOL)ok;
- (void)prepareForHost:(void (^)(BOOL))completion;
- (void)completePrepare:(BOOL)ok;
@end

@implementation HuskWeb
- (instancetype)initWithId:(int)wid
{
    self = [super init];
    _wid = wid;
    _scripts = [NSMutableArray array];
    WKWebViewConfiguration *c = [[WKWebViewConfiguration alloc] init];
    c.websiteDataStore = data_store();
    cookies_watch();
    [c setURLSchemeHandler:self forURLScheme:@"huskapp"];
    c.userContentController = [[WKUserContentController alloc] init];
    [c.userContentController addScriptMessageHandler:self name:@"huskConsole"];
    if (g_host_store) [c.userContentController addUserScript:[[WKUserScript alloc] initWithSource:save_stage_js() injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    [c.userContentController addUserScript:[[WKUserScript alloc] initWithSource:bridge_js() injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
#if TARGET_OS_IPHONE
    c.allowsInlineMediaPlayback = YES;
    c.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
#endif
    @try { [c.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"]; } @catch (NSException *e) {}
    @try { [c setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"]; } @catch (NSException *e) {}
    _web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 10, 10) configuration:c];
    _web.navigationDelegate = self;
    _web.UIDelegate = self;
    _web.customUserAgent = @"Mozilla/5.0 (Linux; Android 14; Husk; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.0.0 Mobile Safari/537.36";
    if (@available(iOS 16.4, macOS 13.3, *)) _web.inspectable = YES;
#if !TARGET_OS_IPHONE
    /* the harness's window is nearly all off screen: without this WebKit calls the page hidden and pages that wait to be seen
       (EA's consent dialog fades in on visibility) never show */
    SEL occl = NSSelectorFromString(@"_setWindowOcclusionDetectionEnabled:");
    if ([_web respondsToSelector:occl]) { void (*f)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))[_web methodForSelector:occl]; f(_web, occl, NO); }
#endif
#if TARGET_OS_IPHONE
    _web.opaque = NO;
    _web.backgroundColor = UIColor.whiteColor;
    _web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#endif
    _web.hidden = YES;
#if !TARGET_OS_IPHONE
    /* the harness's window is off-screen: without this the page counts as hidden (no animation frames, nothing composited) */
    @try { [_web setValue:@NO forKey:@"_windowOcclusionDetectionEnabled"]; } @catch (NSException *e) {}
#endif
    [_web addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:NULL];
    [_web addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    [_web addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:NULL];
    ensure_container();
    if (g_container) [g_container addSubview:_web];
    return self;
}
- (void)teardown
{
    if (!_web) return;
    _closing = YES;
    cancel_pending(_wid);
    [_web removeObserver:self forKeyPath:@"title"];
    [_web removeObserver:self forKeyPath:@"estimatedProgress"];
    [_web removeObserver:self forKeyPath:@"URL"];
    [_web stopLoading];
    [_web.configuration.userContentController removeScriptMessageHandlerForName:@"huskConsole"];
    _web.navigationDelegate = nil;
    _web.UIDelegate = nil;
    [_web removeFromSuperview];
    // Break self -> WKWebView -> configuration -> scheme handler -> self.
    _web = nil;
}
- (void)completeClose:(BOOL)ok
{
    void (^completion)(BOOL) = _closeCompletion;
    if (!completion) return;
    _closeCompletion = nil;
    _blankNavigation = nil;
    [self teardown];
    completion(ok);
}
- (void)closeForHost:(void (^)(BOOL))completion
{
    if (_prepareCompletion) [self completePrepare:NO];
    _closing = YES;
    _closeCompletion = completion;
    cancel_pending(_wid);
    __weak HuskWeb *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weak completeClose:NO];
    });
    // Prepared documents suppress the second lifecycle delivery. Guest-owned
    // destruction that skipped preparation retains the late-bridge rejection.
    [_web evaluateJavaScript:@"window.__huskClosing=true; true" completionHandler:^(id value, NSError *error) {
        HuskWeb *h = weak;
        if (!h.closeCompletion) return;
        if (error) { [h completeClose:NO]; return; }
        [h.web setAllMediaPlaybackSuspended:YES completionHandler:^{
            HuskWeb *h = weak;
            if (h.closeCompletion) {
                // The empty teardown document must not bootstrap application
                // plugins again. Existing document handlers remain installed.
                [h.web.configuration.userContentController removeAllUserScripts];
                h.blankNavigation = [h.web loadHTMLString:@"<!doctype html><title>Closed</title>" baseURL:nil];
            }
        }];
    }];
}
- (void)completePrepare:(BOOL)ok
{
    void (^completion)(BOOL) = _prepareCompletion;
    if (!completion) return;
    _prepareCompletion = nil;
    _prepareFinished = YES;
    _prepareSucceeded = ok;
    if (!ok) g_detach_failed = YES;
    completion(ok);
}
- (void)prepareForHost:(void (^)(BOOL))completion
{
    if (_prepareFinished) { completion(_prepareSucceeded); return; }
    if (_prepareCompletion) {
        // A whole-session stop can join a direct WebView.destroy in progress.
        void (^previous)(BOOL) = _prepareCompletion;
        _prepareCompletion = ^(BOOL ok) { previous(ok); completion(ok); };
        return;
    }
    if (!_web || _closing) { g_detach_failed = YES; completion(NO); return; }
    _prepareStarted = YES;
    _prepareCompletion = completion;
    // Settle an ordinary pending dialog/navigation, but keep accepted plugin
    // calls alive: cancelling their prompt would silently discard a save.
    cancel_pending_except_bridge(_wid, YES);
    __weak HuskWeb *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HuskWeb *h = weak;
        if (h.prepareCompletion) { tl_log_line("javaapp: WebView save stage timed out"); [h completePrepare:NO]; }
    });
    [_web setAllMediaPlaybackSuspended:YES completionHandler:^{
        HuskWeb *h = weak;
        if (!h.prepareCompletion) return;
        [h.web callAsyncJavaScript:@"return await window.__huskPrepareClose();" arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld
            completionHandler:^(id result, NSError *error) {
                HuskWeb *h = weak;
                if (!h.prepareCompletion) return;
                if (error) tl_log_line("javaapp: WebView save stage failed: %s", error.localizedDescription.UTF8String);
                [h completePrepare:!error && [result isKindOfClass:NSNumber.class] && [result boolValue]];
            }];
    }];
}
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)o change:(NSDictionary *)ch context:(void *)ctx
{
    if ([kp isEqualToString:@"title"]) emit(@"t", _wid, @[ _web.title ?: @"" ]);
    else if ([kp isEqualToString:@"estimatedProgress"]) emit(@"p", _wid, @[ [NSString stringWithFormat:@"%d", (int)(_web.estimatedProgress * 100)] ]);
    else [self history];
}
- (void)history
{
    emit(@"h", _wid, @[ _web.canGoBack ? @"1" : @"0", _web.canGoForward ? @"1" : @"0", _web.URL.absoluteString ?: @"" ]);
}
- (int)park:(id)thing kind:(char)kind
{
    int call = g_next_call++;
    HuskWebPending *pending = [HuskWebPending new];
    pending.value = thing; pending.kind = kind; pending.wid = _wid;
    g_pending[@(call)] = pending;
    return call;
}

/* navigation */
- (void)webView:(WKWebView *)w decidePolicyForNavigationAction:(WKNavigationAction *)act decisionHandler:(void (^)(WKNavigationActionPolicy))decide
{
    if (_closing) { decide([act.request.URL.absoluteString isEqual:@"about:blank"] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel); return; }
    if (g_host_preparing || _prepareStarted) { decide(WKNavigationActionPolicyCancel); return; }
    NSURL *u = act.request.URL;
    NSString *scheme = u.scheme.lowercaseString ?: @"";
    bool main = act.targetFrame == nil || act.targetFrame.isMainFrame;
    if (!act.targetFrame) {                             /* target=_blank / window.open: Android loads it in this view */
        decide(WKNavigationActionPolicyCancel);
        [w loadRequest:act.request];
        return;
    }
    if (_apiLoad && main) { _apiLoad = false; decide(WKNavigationActionPolicyAllow); return; }
    bool web = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"huskapp"] ||
               [scheme isEqualToString:@"about"] || [scheme isEqualToString:@"data"] || [scheme isEqualToString:@"blob"] || [scheme isEqualToString:@"file"];
    if (!main && web) { decide(WKNavigationActionPolicyAllow); return; }
    int call = [self park:[decide copy] kind:'o'];
    emit(@"o", _wid, @[ [NSString stringWithFormat:@"%d", call], u.absoluteString ?: @"", main ? @"1" : @"0",
                        act.navigationType == WKNavigationTypeLinkActivated ? @"1" : @"0", act.request.HTTPMethod ?: @"GET", web ? @"1" : @"0" ]);
}
- (void)webView:(WKWebView *)w didStartProvisionalNavigation:(WKNavigation *)n { emit(@"s", _wid, @[ w.URL.absoluteString ?: @"" ]); }
- (void)webView:(WKWebView *)w didCommitNavigation:(WKNavigation *)n { emit(@"m", _wid, @[ w.URL.absoluteString ?: @"" ]); [self history]; }
- (void)webView:(WKWebView *)w didFinishNavigation:(WKNavigation *)n {
    if (_closing) { if (n == _blankNavigation) [self completeClose:YES]; return; }
    [self history]; emit(@"f", _wid, @[ w.URL.absoluteString ?: @"" ]);
}
- (void)failed:(NSError *)e
{
    if ([e.domain isEqualToString:NSURLErrorDomain] && e.code == NSURLErrorCancelled) return;
    if ([e.domain isEqualToString:@"WebKitErrorDomain"] && e.code == 102) return;      /* frame load interrupted by a policy change */
    NSString *url = [e.userInfo[NSURLErrorFailingURLStringErrorKey] description] ?: _web.URL.absoluteString ?: @"";
    emit(@"E", _wid, @[ [NSString stringWithFormat:@"%ld", (long)e.code], e.localizedDescription ?: @"", url ]);
}
- (void)webView:(WKWebView *)w didFailNavigation:(WKNavigation *)n withError:(NSError *)e { if (_closing) { if (n == _blankNavigation) [self completeClose:NO]; } else [self failed:e]; }
- (void)webView:(WKWebView *)w didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)e { if (_closing) { if (n == _blankNavigation) [self completeClose:NO]; } else [self failed:e]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)w { if (g_host_store) g_detach_failed = YES; [self completePrepare:NO]; if (_closing) [self completeClose:NO]; else emit(@"g", _wid, @[]); }

/* dialogs and the bridge */
- (void)webView:(WKWebView *)w runJavaScriptAlertPanelWithMessage:(NSString *)msg initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(void))done
{
    if (_closing || g_host_closing || g_host_preparing || _prepareStarted) { done(); return; }
    int call = [self park:[done copy] kind:'A'];
    emit(@"A", _wid, @[ [NSString stringWithFormat:@"%d", call], f.request.URL.absoluteString ?: @"", msg ?: @"" ]);
}
- (void)webView:(WKWebView *)w runJavaScriptConfirmPanelWithMessage:(NSString *)msg initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(BOOL))done
{
    if (_closing || g_host_closing || g_host_preparing || _prepareStarted) { done(NO); return; }
    int call = [self park:[done copy] kind:'C'];
    emit(@"C", _wid, @[ [NSString stringWithFormat:@"%d", call], f.request.URL.absoluteString ?: @"", msg ?: @"" ]);
}
- (void)webView:(WKWebView *)w runJavaScriptTextInputPanelWithPrompt:(NSString *)msg defaultText:(NSString *)def initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(NSString *))done
{
    if (_closing || g_host_closing) {
        // Android has ended: a pagehide handler cannot still save through a
        // Java plugin. Reject the receipt instead of silently losing that call.
        if (g_host_store && [msg hasPrefix:@"husk:"]) {
            g_detach_failed = YES;
            tl_log_line("javaapp: WebView requested a Java bridge call after destruction");
        }
        done(nil); return;
    }
    BOOL bridge = [msg hasPrefix:@"husk:"];
    if ((g_host_preparing && (!bridge || g_host_prepared)) || (_prepareStarted && (!bridge || _prepareFinished))) {
        if (bridge) g_detach_failed = YES;
        done(nil); return;
    }
    int call = [self park:[done copy] kind:bridge ? 'j' : 'P'];
    if (bridge) emit(@"j", _wid, @[ [NSString stringWithFormat:@"%d", call], [msg substringFromIndex:5] ]);
    else emit(@"P", _wid, @[ [NSString stringWithFormat:@"%d", call], f.request.URL.absoluteString ?: @"", msg ?: @"", def ?: @"" ]);
}
- (WKWebView *)webView:(WKWebView *)w createWebViewWithConfiguration:(WKWebViewConfiguration *)c forNavigationAction:(WKNavigationAction *)act windowFeatures:(WKWindowFeatures *)wf
{
    if (g_host_preparing || g_host_closing || _prepareStarted) return nil;
    [w loadRequest:act.request];
    return nil;
}
- (void)webViewDidClose:(WKWebView *)w { emit(@"x", _wid, @[]); }
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)m
{
    NSDictionary *d = [m.body isKindOfClass:NSDictionary.class] ? m.body : @{};
    if (g_host_store && ([d[@"saveFailed"] boolValue] || [d[@"closing"] boolValue])) {
        g_detach_failed = YES;
        tl_log_line("javaapp: WebView save or late Java bridge call failed");
        return;
    }
    if (_closing || g_host_closing) return;
    emit(@"c", _wid, @[ [NSString stringWithFormat:@"%@", d[@"l"] ?: @0], [NSString stringWithFormat:@"%@", d[@"m"] ?: @""],
                        [NSString stringWithFormat:@"%@", d[@"s"] ?: @""], [NSString stringWithFormat:@"%@", d[@"n"] ?: @0] ]);
}

/* the app's own content */
- (void)webView:(WKWebView *)w startURLSchemeTask:(id<WKURLSchemeTask>)task
{
    if (_closing || g_host_closing || g_host_preparing || _prepareStarted) { [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]]; return; }
    int call = [self park:task kind:'r'];
    NSURLRequest *r = task.request;
    NSMutableArray *f = [NSMutableArray arrayWithArray:@[ [NSString stringWithFormat:@"%d", call], r.URL.absoluteString ?: @"", r.HTTPMethod ?: @"GET",
                                                          r.mainDocumentURL && [r.mainDocumentURL isEqual:r.URL] ? @"1" : @"0" ]];
    [r.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) { [f addObject:k]; [f addObject:v]; }];
    emit(@"r", _wid, f);
}
- (void)webView:(WKWebView *)w stopURLSchemeTask:(id<WKURLSchemeTask>)task
{
    for (NSNumber *k in g_pending.allKeys) if (g_pending[k].value == task) { [g_pending[k].network cancel]; [g_pending removeObjectForKey:k]; }
}
@end

/* ---- husk.Web's natives: the main thread does the work */

static NSString *nstr(jobj *s) { const char *u = s ? tl_jni_string(s) : NULL; return u ? [NSString stringWithUTF8String:u] : nil; }
static NSData *nbytes(jobj *b) { return b && b->kind == TL_K_PRIM_ARRAY ? [NSData dataWithBytes:b->arr.data length:b->arr.len] : nil; }
static NSArray<NSString *> *nstrs(jobj *arr)
{
    NSMutableArray *out = [NSMutableArray array];
    if (arr && arr->kind == TL_K_OBJ_ARRAY) for (uint32_t i = 0; i < arr->oarr.len; i++) [out addObject:nstr(arr->oarr.v[i]) ?: @""];
    return out;
}
static void on_main(dispatch_block_t b) { dispatch_async(dispatch_get_main_queue(), ^{ if (!g_host_closing) b(); }); }
static void dispatch_sync_main_safe(dispatch_block_t b) { if ([NSThread isMainThread]) b(); else dispatch_async(dispatch_get_main_queue(), b); }
static HuskWeb *view_of(int wid) { return g_views[@(wid)]; }

static void retire_view(HuskWeb *h)
{
    if (!h) return;
    if (!g_host_store) { [h teardown]; return; }
    dispatch_group_enter(g_detaching);
    [h closeForHost:^(BOOL ok) {
        if (!ok) g_detach_failed = YES;
        dispatch_group_leave(g_detaching);
        (void)h; // Keep the view owner alive until its asynchronous teardown.
    }];
}

static void update_hits(int wid, bool visible, bool touchable, CGRect r)
{
    pthread_mutex_lock(&g_hit_lock);
    int i = 0;
    while (i < g_nhits && g_hits[i].id != wid) i++;
    if (i == g_nhits && g_nhits < 16) g_nhits++;
    if (i < 16) g_hits[i] = (hit_rect){ wid, visible, touchable, (float)r.origin.x, (float)r.origin.y, (float)r.size.width, (float)r.size.height };
    int n = 0;
    for (int k = 0; k < g_nhits; k++) if (g_hits[k].visible) n++;
    pthread_mutex_unlock(&g_hit_lock);
    atomic_store(&g_visible_webs, n);
}
static void forget_hits(int wid)
{
    pthread_mutex_lock(&g_hit_lock);
    for (int i = 0; i < g_nhits; i++) if (g_hits[i].id == wid) { g_hits[i] = g_hits[--g_nhits]; break; }
    int n = 0;
    for (int k = 0; k < g_nhits; k++) if (g_hits[k].visible) n++;
    pthread_mutex_unlock(&g_hit_lock);
    atomic_store(&g_visible_webs, n);
}

NAT(W_create)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    on_main(^{
        if (g_host_preparing) { g_detach_failed = YES; return; }
        if (!g_views) { g_views = [NSMutableDictionary dictionary]; g_pending = [NSMutableDictionary dictionary]; }
        if (!g_views[@(wid)]) g_views[@(wid)] = [[HuskWeb alloc] initWithId:wid];
    });
    return true;
}
static void complete_guest_destroy(HuskWeb *h)
{
    if (!h.waitingForDestroyAck) return;
    h.waitingForDestroyAck = NO;
    [h closeForHost:^(BOOL ok) {
        if (!ok) g_detach_failed = YES;
        [g_retiring removeObjectForKey:@(h.wid)];
        dispatch_group_leave(g_detaching);
    }];
}

NAT(W_destroy)
{
    (void)self;
    int wid = a[0].i;
    // The host store is installed before AppMain starts and never changes.
    // Other hosts retain the original synchronous Java registry removal.
    *ret = Z(g_host_store != nil);
    forget_hits(wid);
    on_main(^{
        if (g_retiring[@(wid)]) return;
        HuskWeb *h = view_of(wid);
        [g_views removeObjectForKey:@(wid)];
        if (atomic_load(&g_visible_webs) == 0) set_screen_opaque(true);
        if (!h || !g_host_store || g_host_prepared) {
            retire_view(h);
            if (g_host_store) emit(@"d", wid, @[]);
            return;
        }
        // Keep the Java object and its plugins reachable until preparation
        // and the JavaBridge -> AppMain barrier acknowledge accepted work.
        g_retiring[@(wid)] = h;
        dispatch_group_enter(g_detaching);
        [h prepareForHost:^(BOOL ok) {
            if (!ok) g_detach_failed = YES;
            h.waitingForDestroyAck = YES;
            emit(@"d", wid, @[]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (!h.waitingForDestroyAck) return;
                tl_log_line("javaapp: WebView Java destroy acknowledgement timed out");
                g_detach_failed = YES;
                complete_guest_destroy(h);
            });
        }];
    });
    return true;
}
NAT(W_destroyReady)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    on_main(^{ complete_guest_destroy(g_retiring[@(wid)]); });
    return true;
}
NAT(W_frame)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    bool vis = a[5].i != 0, touchable = a[6].i != 0;
    CGRect r = CGRectMake(a[1].i / g_scale, a[2].i / g_scale, a[3].i / g_scale, a[4].i / g_scale);
    update_hits(wid, vis, touchable, r);
    on_main(^{
        HuskWeb *h = view_of(wid);
        if (!h) return;
        /* the screen may have had no superview when the web view was made */
        if (!g_container) ensure_container();
        if (g_container && !h.web.superview) [g_container addSubview:h.web];
#if TARGET_OS_IPHONE
        /* the back swipe from the screen's edge wins over the page's own scrolling */
        if (!h.edgeLinked) {
            for (UIGestureRecognizer *g in g_container.gestureRecognizers)
                if ([g isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) { [h.web.scrollView.panGestureRecognizer requireGestureRecognizerToFail:g]; h.edgeLinked = true; }
        }
#endif
#if TARGET_OS_IPHONE
        if (g_screen && g_container && g_container.superview == g_screen.superview && !CGRectEqualToRect(g_container.frame, g_screen.frame)) g_container.frame = g_screen.frame;
#endif
        h.web.frame = r;
        h.web.hidden = !vis;
        set_screen_opaque(atomic_load(&g_visible_webs) == 0);
    });
    return true;
}
NAT(W_load)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    NSString *url = nstr(a[1].l);
    NSArray *hdr = nstrs(a[2].l);
    NSData *body = nbytes(a[3].l);
    on_main(^{
        if (g_host_preparing) return;
        HuskWeb *h = view_of(wid);
        NSURL *u = url ? [NSURL URLWithString:url] : nil;
        if (!h || !u) { tl_log_line("web: cannot load %s", url.UTF8String ?: "(null)"); return; }
        NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u];
        for (NSUInteger i = 0; i + 1 < hdr.count; i += 2) [r setValue:hdr[i + 1] forHTTPHeaderField:hdr[i]];
        if (body) { r.HTTPMethod = @"POST"; r.HTTPBody = body; }
        h.apiLoad = true;
        if (u.isFileURL) [h.web loadFileURL:u allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
        else [h.web loadRequest:r];
    });
    return true;
}
NAT(W_loadData)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    NSData *data = nbytes(a[1].l);
    NSString *mime = nstr(a[2].l) ?: @"text/html", *enc = nstr(a[3].l) ?: @"utf-8", *base = nstr(a[4].l);
    on_main(^{
        if (g_host_preparing) return;
        HuskWeb *h = view_of(wid);
        if (!h) return;
        h.apiLoad = true;
        /* Android lets a page loaded without a base URL use file:// frames and images when file access is on (EA's consent
           dialog is made of iframes on files in the app's folder); WebKit only lets a file:// page do that, so such a page gets
           the app's data folder as its base */
        NSURL *b = base.length && ![base isEqualToString:@"about:blank"] ? [NSURL URLWithString:base] : nil;
        if (!b) { extern const char *tl_data_dir(void); b = [NSURL fileURLWithPath:[NSString stringWithUTF8String:tl_data_dir()] isDirectory:YES]; }
        [h.web loadData:data ?: [NSData data] MIMEType:mime characterEncodingName:enc baseURL:b];
    });
    return true;
}
NAT(W_eval)
{
    (void)self; (void)ret;
    int wid = a[0].i, cb = a[2].i;
    NSString *js = nstr(a[1].l) ?: @"";
    on_main(^{
        HuskWeb *h = view_of(wid) ?: g_retiring[@(wid)];
        if (!h) return;
        if (g_retiring[@(wid)] && h.prepareFinished) { g_detach_failed = YES; return; }
        if (!cb) { [h.web evaluateJavaScript:js completionHandler:nil]; return; }
        /* Android hands the callback the result as JSON */
        NSData *q = [NSJSONSerialization dataWithJSONObject:@[ js ] options:0 error:nil];
        NSString *quoted = [[NSString alloc] initWithData:q encoding:NSUTF8StringEncoding];
        NSString *wrapped = [NSString stringWithFormat:@"(function(){var r=(0,eval)(%@[0]);try{var s=JSON.stringify(r);return s===undefined?'null':s}catch(e){return 'null'}})()", quoted];
        [h.web evaluateJavaScript:wrapped completionHandler:^(id result, NSError *err) {
            if (err) tl_log_line("web: evaluateJavascript: %s", err.localizedDescription.UTF8String);
            emit(@"v", wid, @[ [NSString stringWithFormat:@"%d", cb], [result isKindOfClass:NSString.class] ? result : @"null" ]);
        }];
    });
    return true;
}
NAT(W_userScript)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    NSString *js = nstr(a[1].l) ?: @"";
    on_main(^{
        HuskWeb *h = view_of(wid);
        if (!h) return;
        [h.scripts addObject:js];
        [h.web.configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:js injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [h.web evaluateJavaScript:js completionHandler:nil];      /* and the page already showing */
    });
    return true;
}
NAT(W_settings)
{
    (void)self; (void)ret;
    int wid = a[0].i, zoom = a[3].i;
    bool js = a[1].i != 0, gesture = a[4].i != 0;
    NSString *ua = nstr(a[2].l);
    on_main(^{
        HuskWeb *h = view_of(wid);
        if (!h) return;
        if (@available(iOS 14.0, macOS 11.0, *)) h.web.configuration.defaultWebpagePreferences.allowsContentJavaScript = js;
        else h.web.configuration.preferences.javaScriptEnabled = js;
        if (ua.length) h.web.customUserAgent = ua;
        if (@available(iOS 14.0, macOS 11.0, *)) h.web.pageZoom = zoom > 0 ? zoom / 100.0 : 1.0;
        (void)gesture;
    });
    return true;
}
NAT(W_go)
{
    (void)self; (void)ret;
    int wid = a[0].i, cmd = a[1].i;
    on_main(^{
        if (g_host_preparing) return;
        HuskWeb *h = view_of(wid);
        if (!h) return;
        switch (cmd) {
        case 0: [h.web goBack]; break;
        case 1: [h.web goForward]; break;
        case 2: [h.web reload]; break;
        case 3: [h.web stopLoading]; break;
        }
    });
    return true;
}
NAT(W_background)
{
    (void)self; (void)ret;
    int wid = a[0].i;
    uint32_t c = (uint32_t)a[1].i;
    on_main(^{
        HuskWeb *h = view_of(wid);
        if (!h) return;
#if TARGET_OS_IPHONE
        UIColor *col = [UIColor colorWithRed:((c >> 16) & 255) / 255.0 green:((c >> 8) & 255) / 255.0 blue:(c & 255) / 255.0 alpha:(c >> 24) / 255.0];
        h.web.backgroundColor = col;
        h.web.scrollView.backgroundColor = col;
        h.web.opaque = (c >> 24) == 255;
#else
        @try { [h.web setValue:@((c >> 24) == 255) forKey:@"drawsBackground"]; } @catch (NSException *e) {}
#endif
    });
    return true;
}
NAT(W_reply)
{
    (void)self; (void)ret;
    int call = a[0].i;
    NSString *r = nstr(a[1].l);
    bool isNull = a[1].l == NULL;
    on_main(^{
        HuskWebPending *pending = g_pending[@(call)];
        if (!pending || pending.kind == 'r') return;
        id thing = pending.value;
        [g_pending removeObjectForKey:@(call)];
        switch (pending.kind) {
        case 'o': ((void (^)(WKNavigationActionPolicy))thing)([r isEqualToString:@"\x01nav-allow"] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel); break;
        case 'A': ((void (^)(void))thing)(); break;
        case 'C': ((void (^)(BOOL))thing)([r isEqualToString:@"\x01yes"]); break;
        case 'j': {
            HuskWeb *owner = g_views[@(pending.wid)] ?: g_retiring[@(pending.wid)];
            if (g_host_preparing || owner.prepareStarted) {
                NSData *data = [r dataUsingEncoding:NSUTF8StringEncoding];
                id reply = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                if (![reply isKindOfClass:NSDictionary.class] || reply[@"e"]) g_detach_failed = YES;
            }
            ((void (^)(NSString *))thing)(isNull ? nil : r); break;
        }
        case 'P': ((void (^)(NSString *))thing)(isNull ? nil : r); break;
        }
    });
    return true;
}
NAT(W_respond)
{
    (void)self; (void)ret;
    int call = a[0].i, status = a[1].i;
    NSString *reason = nstr(a[2].l), *mime = nstr(a[3].l), *enc = nstr(a[4].l);
    NSArray *hdr = nstrs(a[5].l);
    NSData *body = nbytes(a[6].l);
    on_main(^{
        HuskWebPending *pending = g_pending[@(call)];
        if (!pending || pending.kind != 'r') return;
        id<WKURLSchemeTask> task = pending.value;
        if (status == 0) {
            /* not the app's: fetch the real URL (reason) and hand that over */
            NSURL *real = reason ? [NSURL URLWithString:reason] : nil;
            if (!real) { [g_pending removeObjectForKey:@(call)]; [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]]; return; }
            NSMutableURLRequest *r = [task.request mutableCopy];
            r.URL = real;
            /* the page's cookies are the data store's, both ways */
            r.HTTPShouldHandleCookies = NO;
            NSString *ck = cookie_header(real);
            if (ck) [r setValue:ck forHTTPHeaderField:@"Cookie"];
            dispatch_group_enter(network_requests());
            pending.network = [NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    dispatch_group_leave(network_requests());
                    if (g_host_closing || !g_pending[@(call)]) return;
                    [g_pending removeObjectForKey:@(call)];
                    if (err) { [task didFailWithError:err]; return; }
                    NSHTTPURLResponse *hr = [resp isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)resp : nil;
                    if (hr) cookies_put([NSHTTPCookie cookiesWithResponseHeaderFields:hr.allHeaderFields forURL:hr.URL ?: real]);
                    NSHTTPURLResponse *out = [[NSHTTPURLResponse alloc] initWithURL:task.request.URL statusCode:hr ? hr.statusCode : 200 HTTPVersion:@"HTTP/1.1"
                                                                      headerFields:hr ? hr.allHeaderFields : @{ @"Content-Type": resp.MIMEType ?: @"application/octet-stream" }];
                    [task didReceiveResponse:out];
                    if (d) [task didReceiveData:d];
                    [task didFinish];
                });
            }];
            [pending.network resume];
            return;
        }
        [g_pending removeObjectForKey:@(call)];
        if (status < 0) { [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]]; return; }
        NSMutableDictionary *h = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i + 1 < hdr.count; i += 2) h[hdr[i]] = hdr[i + 1];
        NSString *type = mime.length ? mime : @"application/octet-stream";
        if (enc.length && ![type containsString:@"charset"]) type = [NSString stringWithFormat:@"%@; charset=%@", type, enc];
        if (!h[@"Content-Type"] && !h[@"content-type"]) h[@"Content-Type"] = type;
        if (!h[@"Access-Control-Allow-Origin"]) h[@"Access-Control-Allow-Origin"] = @"*";
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:task.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:h];
        [task didReceiveResponse:resp];
        if (body.length) [task didReceiveData:body];
        [task didFinish];
    });
    return true;
}
NAT(W_poll)
{
    (void)self; (void)a;
    pthread_mutex_lock(&g_ev_lock);
    int n = g_nev;
    if (!n) { pthread_mutex_unlock(&g_ev_lock); *ret = L(NULL); return true; }
    jobj *arr = tl_jni_new_obj_array(tl_jni_class("java/lang/String"), (uint32_t)n);
    arr->cls = tl_jni_class("[Ljava/lang/String;");
    arr->refs = 1u << 30;
    for (int i = 0; i < n; i++) { arr->oarr.v[i] = dvm_new_string_utf8(g_ev[i]); free(g_ev[i]); }
    g_nev = 0;
    pthread_mutex_unlock(&g_ev_lock);
    *ret = L(arr);
    return true;
}

/* ---- CookieManager: the app's data store's cookies */
NAT(W_app)
{
    (void)self; (void)ret;
    NSString *pkg = nstr(a[0].l);
    dispatch_sync_main_safe(^{ if (g_host_closing) return; if (!g_app) g_app = pkg; cookies_watch(); });
    return true;
}
NAT(W_cookieSet)
{
    (void)self; (void)ret;
    NSString *u = nstr(a[0].l), *v = nstr(a[1].l);
    NSURL *url = u ? [NSURL URLWithString:u] : nil;
    if (!url || !v) { *ret = Z(false); return true; }
    if (!url.host && url.scheme == nil) url = [NSURL URLWithString:[@"https://" stringByAppendingString:u]];     /* Android takes "example.com" too */
    NSArray *cs = [NSHTTPCookie cookiesWithResponseHeaderFields:@{ @"Set-Cookie": v } forURL:url];
    cookies_put(cs);
    *ret = Z(cs.count > 0);
    return true;
}
NAT(W_cookieGet)
{
    (void)self;
    NSString *u = nstr(a[0].l);
    NSURL *url = u ? [NSURL URLWithString:u] : nil;
    if (url && !url.host) url = [NSURL URLWithString:[@"https://" stringByAppendingString:u]];
    NSString *h = cookie_header(url);
    *ret = L(h ? tl_jni_new_string(h.UTF8String) : NULL);
    return true;
}
NAT(W_cookieClear)
{
    (void)self;
    bool sessionOnly = a[0].z;
    NSMutableArray *gone = [NSMutableArray array], *kept = [NSMutableArray array];
    pthread_mutex_lock(&g_cookie_lock);
    for (NSHTTPCookie *c in g_cookies) [(sessionOnly && !c.isSessionOnly ? kept : gone) addObject:c];
    g_cookies = kept;
    pthread_mutex_unlock(&g_cookie_lock);
    for (NSHTTPCookie *c in gone) {
        dispatch_group_enter(cookie_writes());
        dispatch_async(dispatch_get_main_queue(), ^{
            [data_store().httpCookieStore deleteCookie:c completionHandler:^{ dispatch_group_leave(cookie_writes()); }];
        });
    }
    *ret = Z(gone.count > 0);
    return true;
}
NAT(W_cookieAny)
{
    (void)self; (void)a;
    pthread_mutex_lock(&g_cookie_lock); bool any = g_cookies.count > 0; pthread_mutex_unlock(&g_cookie_lock);
    *ret = Z(any);
    return true;
}

static const struct { const char *name, *sig; dvm_native_fn fn; } k_web[] = {
    { "create", "(I)V", W_create },
    { "destroy", "(I)Z", W_destroy },
    { "destroyReady", "(I)V", W_destroyReady },
    { "frame", "(IIIIIZZ)V", W_frame },
    { "load", "(ILjava/lang/String;[Ljava/lang/String;[B)V", W_load },
    { "loadData", "(I[BLjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", W_loadData },
    { "eval", "(ILjava/lang/String;I)V", W_eval },
    { "userScript", "(ILjava/lang/String;)V", W_userScript },
    { "settings", "(IZLjava/lang/String;IZ)V", W_settings },
    { "go", "(II)V", W_go },
    { "background", "(II)V", W_background },
    { "reply", "(ILjava/lang/String;)V", W_reply },
    { "respond", "(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;[B)V", W_respond },
    { "poll", "()[Ljava/lang/String;", W_poll },
    { "app", "(Ljava/lang/String;)V", W_app },
    { "cookieSet", "(Ljava/lang/String;Ljava/lang/String;)Z", W_cookieSet },
    { "cookieGet", "(Ljava/lang/String;)Ljava/lang/String;", W_cookieGet },
    { "cookieClear", "(Z)Z", W_cookieClear },
    { "cookieAny", "()Z", W_cookieAny },
    { NULL, NULL, NULL },
};
dvm_native_fn tl_web_native(const char *name, const char *sig);
dvm_native_fn tl_web_native(const char *name, const char *sig)
{
    for (int i = 0; k_web[i].name; i++) if (!strcmp(k_web[i].name, name) && !strcmp(k_web[i].sig, sig)) return k_web[i].fn;
    return NULL;
}

/* ---- the host's side */

void tl_web_attach(void *screen_view, void *container, float scale, bool fresh)
{
    HView *view = (__bridge HView *)screen_view, *box = (__bridge HView *)container;
    float s = scale > 0 ? scale : 1;
    dispatch_block_t b = ^{
        if (fresh) {
            /* a new app on a new screen: whatever the last one left goes */
            for (HuskWeb *h in g_views.allValues) [h teardown];
            [g_views removeAllObjects];
            cancel_pending(0);
            pthread_mutex_lock(&g_hit_lock);
            g_nhits = 0;
            pthread_mutex_unlock(&g_hit_lock);
            atomic_store(&g_visible_webs, 0);
        } else {
            /* the same app shown again on a new screen: its pages move over */
            for (HuskWeb *h in g_views.allValues) if (box) [box addSubview:h.web];
        }
        if (g_container != box) [g_container removeFromSuperview];
        g_container = box;
        g_screen = view;
        g_scale = s;
        set_screen_opaque(atomic_load(&g_visible_webs) == 0);
    };
    if ([NSThread isMainThread]) b(); else dispatch_sync(dispatch_get_main_queue(), b);
}

bool tl_web_set_host_store(NSUUID *identifier)
{
    if (!NSThread.isMainThread || !identifier || g_store || g_host_store) return false;
    g_host_store = identifier;
    g_detaching = dispatch_group_create();
    g_retiring = [NSMutableDictionary dictionary];
    return true;
}

void tl_web_prepare_for_host(void (^completion)(BOOL))
{
    NSCAssert(NSThread.isMainThread, @"WebKit preparation must run on main");
    if (!g_host_store || g_host_preparing || g_host_closing) { g_detach_failed = YES; completion(NO); return; }
    g_host_preparing = YES;
    dispatch_group_t preparing = dispatch_group_create();
    for (HuskWeb *h in g_views.allValues) {
        dispatch_group_enter(preparing);
        [h prepareForHost:^(BOOL ok) {
            if (!ok) g_detach_failed = YES;
            dispatch_group_leave(preparing);
            (void)h;
        }];
    }
    dispatch_group_notify(preparing, dispatch_get_main_queue(), ^{
        // Directly destroyed views can be absent from g_views while their
        // plugins/UI writes are still saving. Android must remain alive.
        dispatch_group_notify(g_detaching, dispatch_get_main_queue(), ^{
            g_host_prepared = YES;
            completion(!g_detach_failed);
        });
    });
}

/* This is a document-detach + WebKit ownership acknowledgement, not a disk
 * fsync claim. The caller separately checks Android destruction and storage. */
void tl_web_close_for_host(void (^completion)(BOOL, NSDictionary *))
{
    NSCAssert(NSThread.isMainThread, @"WebKit close must run on main");
    if (!g_host_store || g_host_closing) { completion(NO, nil); return; }
    g_host_closing = YES;
    BOOL used = g_store != nil;
    for (HuskWeb *h in g_views.allValues) retire_view(h);
    [g_views removeAllObjects];
    cancel_pending(0);
    // Both the view and cookie barriers may finish asynchronously. A missing
    // callback must never become a successful receipt just because time passed.
    __block void (^done)(BOOL, NSDictionary *) = [completion copy];
    void (^finish)(BOOL) = ^(BOOL ok) {
        if (!done) return;
        void (^callback)(BOOL, NSDictionary *) = done; done = nil;
        if (g_cookie_watch) [g_store.httpCookieStore removeObserver:g_cookie_watch];
        g_cookie_watch = nil;
        tl_web_attach(NULL, NULL, 1, true);
        NSDictionary *receipt = @{@"lifecycle":used ? @"detached" : @"unused",
            @"storage":used ? @"webkit-managed" : @"unused", @"store":g_host_store.UUIDString,
            @"saveStage":g_host_prepared ? @"prepared" : @"not-requested"};
        callback(ok && !g_detach_failed, receipt);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ finish(NO); });
    dispatch_group_notify(g_detaching, dispatch_get_main_queue(), ^{
        dispatch_group_notify(network_requests(), dispatch_get_main_queue(), ^{
            dispatch_group_notify(cookie_writes(), dispatch_get_main_queue(), ^{
                if (!used) { finish(YES); return; }
                [g_store.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
                    [g_store fetchDataRecordsOfTypes:WKWebsiteDataStore.allWebsiteDataTypes completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
                        finish(YES);
                    }];
                }];
            });
        });
    });
}

void tl_web_evaluate_for_host(int wid, NSString *script, void (^completion)(id, NSError *))
{
    HuskWeb *h = wid ? g_views[@(wid)] : g_views.count == 1 ? g_views.allValues.firstObject : nil;
    if (g_host_preparing || g_host_closing || !h.web || h.closing) {
        completion(nil, [NSError errorWithDomain:@"HuskWeb" code:1 userInfo:@{NSLocalizedDescriptionKey:@"WebView unavailable"}]); return;
    }
    [h.web evaluateJavaScript:script completionHandler:completion];
}

bool tl_web_hit(float x, float y)
{
    bool hit = false;
    pthread_mutex_lock(&g_hit_lock);
    for (int i = 0; i < g_nhits && !hit; i++) {
        const hit_rect *r = &g_hits[i];
        hit = r->id && r->visible && r->touchable && x >= r->x && y >= r->y && x < r->x + r->w && y < r->y + r->h;
    }
    pthread_mutex_unlock(&g_hit_lock);
    return hit;
}

bool tl_web_any_visible(void) { return atomic_load(&g_visible_webs) > 0; }

#if !TARGET_OS_IPHONE
/* The harness: a run loop on the main thread for WebKit, taps as clicks, and the web views' pixels for screenshots. */
void tl_web_harness_size(int w, int h, float scale)
{
    g_scale = scale > 0 ? scale : 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSView *screen;                          /* g_screen is weak: this keeps the stand-in alive */
        screen = [[HuskFlippedView alloc] initWithFrame:NSMakeRect(0, 0, w / g_scale, h / g_scale)];
        g_screen = screen;
    });
}
void tl_web_main_loop(void)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
    CFRunLoopRun();
}
bool tl_web_tap(float px, float py)
{
    float x = px / g_scale, y = py / g_scale;
    int wid = 0;
    float ox = 0, oy = 0;
    pthread_mutex_lock(&g_hit_lock);
    for (int i = 0; i < g_nhits; i++) {
        const hit_rect *r = &g_hits[i];
        if (r->id && r->visible && r->touchable && x >= r->x && y >= r->y && x < r->x + r->w && y < r->y + r->h) { wid = r->id; ox = r->x; oy = r->y; break; }
    }
    pthread_mutex_unlock(&g_hit_lock);
    if (!wid) return false;
    float lx = x - ox, ly = y - oy;
    dispatch_async(dispatch_get_main_queue(), ^{
        HuskWeb *h = view_of(wid);
        NSString *js = [NSString stringWithFormat:@"(function(){var e=document.elementFromPoint(%f,%f);if(!e)return 'none';"
                        "['pointerdown','mousedown','pointerup','mouseup'].forEach(function(t){e.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,clientX:%f,clientY:%f}))});"
                        "if(e.focus)e.focus();e.click();return e.tagName+'#'+(e.id||'')+'.'+(e.className||'');})()", lx, ly, lx, ly];
        [h.web evaluateJavaScript:js completionHandler:^(id r, NSError *err) { tl_log_line("web: tap %.0f,%.0f -> %s", lx, ly, [[r description] UTF8String] ?: "?"); }];
    });
    return true;
}
void tl_web_snapshot(const char *png)
{
    NSString *path = [NSString stringWithUTF8String:png];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (HuskWeb *h in g_views.allValues) {
            if (h.web.hidden) continue;
            [h.web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *img, NSError *err) {
                if (!img) { tl_log_line("web: snapshot failed: %s", err.localizedDescription.UTF8String ?: "?"); return; }
                CGImageRef cg = [img CGImageForProposedRect:NULL context:nil hints:nil];
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
                tl_log_line("web: snapshot of %d -> %s", h.wid, png);
            }];
            break;
        }
    });
}
void tl_web_eval_log(const char *js)
{
    NSString *s = [NSString stringWithUTF8String:js];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (HuskWeb *h in g_views.allValues)
            [h.web evaluateJavaScript:s completionHandler:^(id r, NSError *err) { tl_log_line("web: eval -> %s", err ? err.localizedDescription.UTF8String : [[r description] UTF8String] ?: "null"); }];
    });
}
#endif
