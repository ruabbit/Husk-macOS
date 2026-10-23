/* SPDX-License-Identifier: GPL-2.0-or-later */
#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPSKeys.h>
#include "husk-tl-dvm-internal.h"
#include "husk-tl-bionic.h"

int tl_sensors_mac_battery(NSArray<NSDictionary *> *sources);
dvm_native_fn dvm_android_native(const char *, const char *, const char *);
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL host environment %d: %s\n",__LINE__,#c); return 1; } } while (0)

int main(void) { @autoreleasepool {
    NSMutableDictionary *d = [@{@kIOPSTypeKey:@kIOPSInternalBatteryType, @kIOPSIsPresentKey:@YES,
        @kIOPSCurrentCapacityKey:@40, @kIOPSMaxCapacityKey:@80,
        @kIOPSPowerSourceStateKey:@kIOPSBatteryPowerValue, @kIOPSIsChargingKey:@NO} mutableCopy];
    CHECK(tl_sensors_mac_battery(@[d]) == (50 | 3 << 8));
    d[@kIOPSPowerSourceStateKey] = @kIOPSACPowerValue; d[@kIOPSIsChargingKey] = @YES;
    CHECK(tl_sensors_mac_battery(@[d]) == (50 | 2 << 8 | 1 << 16));
    d[@kIOPSIsChargingKey] = @NO;
    CHECK(tl_sensors_mac_battery(@[d]) == (50 | 4 << 8 | 1 << 16));
    d[@kIOPSCurrentCapacityKey] = @80;
    CHECK(tl_sensors_mac_battery(@[d]) == (100 | 5 << 8 | 1 << 16));
    d[@kIOPSCurrentCapacityKey] = @0; d[@kIOPSPowerSourceStateKey] = @kIOPSBatteryPowerValue;
    CHECK(tl_sensors_mac_battery(@[d]) == 3 << 8);
    d[@kIOPSMaxCapacityKey] = @0; CHECK(tl_sensors_mac_battery(@[d]) == -1);
    [d removeObjectForKey:@kIOPSMaxCapacityKey]; CHECK(tl_sensors_mac_battery(@[d]) == -1);
    d[@kIOPSTypeKey] = @kIOPSUPSType;
    int desktop = 100 | 5 << 8 | 1 << 16 | 1 << 24;
    CHECK(tl_sensors_mac_battery(@[d]) == desktop && tl_sensors_mac_battery(@[]) == desktop);
    CHECK(tl_sensors_mac_battery(nil) == -1);
    dvm_native_fn battery = dvm_android_native("husk/Sensors", "battery", "()I");
    dvm_native_fn clock = dvm_android_native("husk/Native", "is24Hour", "()Z");
    CHECK(battery && clock);
    jvalue actual = {0}; CHECK(battery(NULL, NULL, &actual));
    CHECK(actual.i == -1 || ((actual.i & 255) <= 100 && ((actual.i >> 8) & 255) >= 1 && ((actual.i >> 8) & 255) <= 5));
    printf("PASS live Mac power snapshot: packed=%d present=%d\n",actual.i,actual.i >= 0 && !(actual.i & (1 << 24)));
    CHECK(clock(NULL, NULL, &actual));
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:NSLocale.currentLocale];
    CHECK(actual.z == ([pattern rangeOfString:@"a"].location == NSNotFound));
    CHECK(!strcmp(tl_sysprop("persist.sys.timezone"), NSTimeZone.systemTimeZone.name.UTF8String));
    CHECK(!strcmp(tl_sysprop("persist.sys.locale"), NSLocale.preferredLanguages.firstObject.UTF8String));
    CHECK(!strcmp(tl_sysprop("persist.sys.locale"), tl_sysprop("ro.product.locale")));
    printf("PASS host clock, timezone and preferred locale: %s / %s\n", tl_sysprop("persist.sys.timezone"),tl_sysprop("persist.sys.locale"));
    return 0;
} }
