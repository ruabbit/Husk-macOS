cmake_minimum_required(VERSION 3.28)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported native architecture")
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0 CACHE STRING "Provisional deployment floor; requires separate machine validation")
project(HuskMac VERSION 0.2.0 LANGUAGES C OBJC Swift)
if(NOT APPLE OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    message(FATAL_ERROR "HuskMac currently targets native macOS arm64")
endif()
set(CMAKE_C_STANDARD 11)
set(CMAKE_Swift_LANGUAGE_VERSION 5)
add_compile_options("$<$<COMPILE_LANGUAGE:Swift>:-target>" "$<$<COMPILE_LANGUAGE:Swift>:arm64-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}>")
set(CMAKE_Swift_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/swift")
set(CMAKE_BUILD_RPATH "@executable_path/../Frameworks")
set(HUSK_DEPS "${CMAKE_SOURCE_DIR}/build/macos-deps" CACHE PATH "Pinned macOS graphics prefix")
find_package(Python3 REQUIRED COMPONENTS Interpreter)
option(HUSK_BUILD_VM "Build the optional native VMRunner" OFF)
set(HUSK_VM_DEPS "${CMAKE_SOURCE_DIR}/build/macos-vm-deps" CACHE PATH "Pinned VM dependency prefix")
if(NOT EXISTS "${HUSK_DEPS}/lib/libANGLE-shared.dylib" OR NOT EXISTS "${HUSK_DEPS}/lib/MoltenVK.framework")
    message(FATAL_ERROR "Run python3 scripts/build_macos_graphics.py first")
endif()

set(CLASSIC "${CMAKE_SOURCE_DIR}/src/translation-layer")
set(NEXT "${CMAKE_SOURCE_DIR}/src/translation-layer-next")
set(MAC "${CMAKE_SOURCE_DIR}/src/macos")
set(HUSK_JAVA_RUNTIME "${CMAKE_BINARY_DIR}/JavaRuntime" CACHE PATH "Pinned Android Java resources")
if(NOT EXISTS "${HUSK_JAVA_RUNTIME}/runtime-manifest.json")
    message(FATAL_ERROR "Prepare Java resources: scripts/build_java_runtime.sh --image <pinned-vda-v12.qcow2> --output ${HUSK_JAVA_RUNTIME}")
endif()
file(GLOB_RECURSE HUSK_JAVA_SOURCES CONFIGURE_DEPENDS src/java-framework/*.java src/java-framework/gen/*.py)
add_custom_command(OUTPUT "${HUSK_JAVA_RUNTIME}/husk-framework.dex" "${HUSK_JAVA_RUNTIME}/runtime-manifest.json"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build_java_runtime.py --refresh-framework --output ${HUSK_JAVA_RUNTIME}
    DEPENDS ${HUSK_JAVA_SOURCES} scripts/build_java_framework.py scripts/build_java_runtime.py dependencies/java-runtime.lock.json VERBATIM)
add_custom_target(JavaRuntimeResources DEPENDS "${HUSK_JAVA_RUNTIME}/husk-framework.dex" "${HUSK_JAVA_RUNTIME}/runtime-manifest.json")
set(HUSK_ICON_SOURCE "${CMAKE_SOURCE_DIR}/src/app/Husk/Assets.xcassets/AppIcon.appiconset/Icon-Default.png")
set(HUSK_ICON "${CMAKE_BINARY_DIR}/Resources/Husk.icns")
add_custom_command(OUTPUT "${HUSK_ICON}"
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_SOURCE_DIR}/scripts/build_macos_icon.py" "${HUSK_ICON_SOURCE}" "${HUSK_ICON}"
    DEPENDS "${HUSK_ICON_SOURCE}" scripts/build_macos_icon.py VERBATIM)
add_custom_target(MacIcon DEPENDS "${HUSK_ICON}")
set_source_files_properties("${HUSK_ICON}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
add_library(SharedCore STATIC
    ${CLASSIC}/husk-tl-scan.c ${CLASSIC}/husk-tl-zip.c ${CLASSIC}/husk-tl-elf.c
    ${CLASSIC}/husk-tl-json.c ${CLASSIC}/husk-tl-prefs.c ${CLASSIC}/husk-tl-blit.c
    ${MAC}/SharedCore/Archive.c)
target_include_directories(SharedCore PUBLIC ${MAC}/SharedCore PRIVATE ${CLASSIC})
target_link_libraries(SharedCore PUBLIC z "-framework CoreGraphics")

add_library(SharedLibrary STATIC
    ${MAC}/SharedLibrary/Models.swift ${MAC}/SharedLibrary/AtomicFile.swift ${MAC}/SharedLibrary/APKSignature.swift
    ${MAC}/SharedLibrary/LibraryRepository.swift ${MAC}/SharedLibrary/SessionController.swift ${MAC}/SharedLibrary/NativeLaunch.swift ${MAC}/SharedLibrary/VMController.swift
    src/app/Husk/ApkMetadata.swift src/app/Husk/BundleUnpacker.swift)
target_link_libraries(SharedLibrary PUBLIC SharedCore "-framework Security")
target_compile_options(SharedLibrary PRIVATE -I ${MAC}/SharedCore)

add_library(GameActivityRuntime STATIC
    ${CLASSIC}/husk-tl-sound.c
    ${NEXT}/husk-tl-ld.c ${NEXT}/husk-tl-a64.c ${NEXT}/husk-tl-xmem.c ${NEXT}/husk-tl-va.c ${NEXT}/husk-tl-codewrite.c
    ${NEXT}/husk-tl-bionic.c ${NEXT}/husk-tl-bionic-str.c ${NEXT}/husk-tl-bionic-io.c
    ${NEXT}/husk-tl-bionic-net.c ${NEXT}/husk-tl-bionic-pthread.c ${NEXT}/husk-tl-bionic-cxx.c
    ${NEXT}/husk-tl-bionic-ndk.c ${NEXT}/husk-tl-bionic-sys.c ${NEXT}/husk-tl-bionic-ldbl.c ${NEXT}/husk-tl-opensles.c
    ${NEXT}/husk-tl-jni.c ${NEXT}/husk-tl-jni-hle.c ${NEXT}/husk-tl-jni-loop.c
    ${NEXT}/husk-tl-jni-input.c ${NEXT}/husk-tl-jni-assetstream.c ${NEXT}/husk-tl-jni-tls.c
    ${NEXT}/husk-tl-jni-http.c ${NEXT}/husk-tl-jni-security.c ${NEXT}/husk-tl-jni-fmod.c ${NEXT}/husk-tl-jni-gms.c
    ${NEXT}/husk-tl-jni-minecraft.c ${NEXT}/husk-tl-jni-text.c ${NEXT}/husk-tl-jni-audiotrack.c ${NEXT}/husk-tl-dexindex.c
    ${NEXT}/husk-tl-dvm.c ${NEXT}/husk-tl-dvm-boot.c ${NEXT}/husk-tl-dvm-natives.c ${NEXT}/husk-tl-dvm-jvm.c
    ${NEXT}/husk-tl-manifest.c ${NEXT}/husk-tl-dvm-annotations.c ${NEXT}/husk-tl-dvm-proxy.c ${NEXT}/husk-tl-dvm-android.c
    ${NEXT}/husk-tl-dvm-graphics.c ${NEXT}/husk-tl-dvm-audio.c ${NEXT}/husk-tl-dvm-sqlite.c
    ${NEXT}/husk-tl-dvm-media.c ${NEXT}/husk-tl-dvm-sensors.m ${NEXT}/husk-tl-dvm-web.m
    ${NEXT}/husk-tl-dvm-gles10.c ${NEXT}/husk-tl-dvm-gles10ext.c
    ${NEXT}/husk-tl-dvm-gles11.c ${NEXT}/husk-tl-dvm-gles11ext.c
    ${NEXT}/husk-tl-dvm-gles20.c ${NEXT}/husk-tl-dvm-gles30.c
    ${NEXT}/husk-tl-dvm-gles31.c ${NEXT}/husk-tl-dvm-gles32.c
    ${NEXT}/husk-tl-egl.c ${NEXT}/husk-tl-gameactivity.c ${NEXT}/husk-tl-unity.c ${NEXT}/husk-tl-gamepad.c
    ${NEXT}/husk-tl-nativeactivity.c ${NEXT}/husk-tl-jni-ue4.c
    ${NEXT}/husk-tl-audio.c ${NEXT}/husk-tl-http.m ${NEXT}/husk-tl-vulkan.m)
target_include_directories(GameActivityRuntime PUBLIC ${NEXT} PRIVATE ${CLASSIC})
target_compile_options(GameActivityRuntime PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(GameActivityRuntime PUBLIC SharedCore resolv sqlite3 "-framework Foundation" "-framework Security"
    "-framework AudioToolbox" "-framework QuartzCore" "-framework Metal" "-framework AppKit"
    "-framework CoreText" "-framework ImageIO" "-framework WebKit" "-framework VideoToolbox"
    "-framework CoreMedia" "-framework CoreVideo" "-framework Accelerate")
add_library(NativeRuntime ALIAS GameActivityRuntime)

add_executable(MinecraftProbe tests/macos/MinecraftProbe.c)
target_link_libraries(MinecraftProbe PRIVATE GameActivityRuntime)
add_executable(NativeActivityProbe tests/macos/NativeActivityProbe.m ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(NativeActivityProbe PRIVATE ${MAC}/NativeRunner)
target_compile_options(NativeActivityProbe PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(NativeActivityProbe PRIVATE NativeRuntime "-framework Foundation")

add_executable(NativeRunner MACOSX_BUNDLE ${MAC}/NativeRunner/main.m ${MAC}/NativeRunner/MacGraphics.m
    ${MAC}/NativeRunner/MacAudio.m ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacDiagnostics.c ${MAC}/NativeRunner/MacJavaRuntime.m
    ${MAC}/NativeRunner/MacTextInput.m ${MAC}/NativeRunner/MacRenderView.m "${HUSK_ICON}")
add_dependencies(NativeRunner MacIcon)
target_include_directories(NativeRunner PRIVATE ${HUSK_DEPS}/include tests/macos/fixture)
target_compile_options(NativeRunner PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(NativeRunner PRIVATE NativeRuntime "-framework AppKit" "-framework QuartzCore"
    "-framework Metal" "-framework Security" "-framework GameController" "-framework AudioToolbox")
set_target_properties(NativeRunner PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/NativeRunner/Info.plist.in)

set(MAC_PLAY_SOURCES
    src/app/Husk/Play/Protobuf.swift src/app/Husk/Play/PlayDevice.swift src/app/Husk/Play/PlayAPI.swift
    ${MAC}/Play/GoogleLoginPolicy.swift ${MAC}/Play/GoogleBrowserLogin.swift
    ${MAC}/Play/PlayCredentials.swift ${MAC}/Play/PlayDownload.swift ${MAC}/Play/MacPlayStore.swift)
add_executable(HuskMac MACOSX_BUNDLE ${MAC_PLAY_SOURCES} ${MAC}/Play/PlayStoreView.swift ${MAC}/Play/GoogleLoginView.swift
    ${MAC}/HuskMac/HuskMac.swift ${MAC}/HuskMac/MacCompatibility.swift src/app/Husk/Compatibility.swift "${HUSK_ICON}")
# Swift's whole-module link does not follow the object-level resource copy rule.
add_custom_target(HuskMacResources DEPENDS "${CMAKE_BINARY_DIR}/HuskMac.app/Contents/Resources/Husk.icns")
add_dependencies(HuskMac MacIcon HuskMacResources)
target_compile_options(HuskMac PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(HuskMac PRIVATE SharedLibrary "-framework AppKit" "-framework SwiftUI" "-framework WebKit")
set_target_properties(HuskMac PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/HuskMac/Info.plist.in)

if(HUSK_BUILD_VM)
    if(NOT EXISTS "${HUSK_VM_DEPS}/lib/libqemu-aarch64-softmmu.dylib")
        message(FATAL_ERROR "Run python3 scripts/build_macos_vm.py before enabling HUSK_BUILD_VM")
    endif()
    add_executable(VMRunner MACOSX_BUNDLE ${MAC}/VMRunner/main.m ${MAC}/VMRunner/VMDisplay.m
        ${MAC}/VMRunner/VMConnection.m ${MAC}/VMRunner/VMInstall.m ${MAC}/NativeRunner/MacAudio.m "${HUSK_ICON}")
    add_dependencies(VMRunner MacIcon)
    target_compile_options(VMRunner PRIVATE -fobjc-arc -Wno-deprecated-declarations)
    target_include_directories(VMRunner PRIVATE src/ios-jit ${MAC}/NativeRunner)
    target_link_libraries(VMRunner PRIVATE "${HUSK_VM_DEPS}/lib/libqemu-aarch64-softmmu.dylib"
        "-framework AppKit" "-framework QuartzCore" "-framework Metal" "-framework AudioToolbox")
    set_target_properties(VMRunner PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/VMRunner/Info.plist.in)
    add_custom_target(PackageVM
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/package_macos_vm.py
            --runner "$<TARGET_BUNDLE_DIR:VMRunner>" --deps ${HUSK_VM_DEPS} --graphics ${HUSK_DEPS}
            --destination ${CMAKE_BINARY_DIR}/PackagedVM/VMRunner.app
        DEPENDS VMRunner VERBATIM)
endif()

set(FIXTURES "${CMAKE_BINARY_DIR}/Fixtures")
set(HUSK_PRODUCT "${CMAKE_BINARY_DIR}/Product/HuskMac.app")
add_custom_command(OUTPUT ${FIXTURES}/fixture-catalog.json ${FIXTURES}/OrbitGarden.apk ${FIXTURES}/OrbitGardenDusk.apk
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build_macos_fixture.py --output ${FIXTURES}
    DEPENDS scripts/build_macos_fixture.py tests/macos/fixture/orbit.c tests/macos/fixture/orbit.h VERBATIM)
add_custom_target(Fixtures DEPENDS ${FIXTURES}/fixture-catalog.json ${FIXTURES}/OrbitGarden.apk ${FIXTURES}/OrbitGardenDusk.apk)
set(VM_PACKAGE_ARGUMENTS)
set(VM_PACKAGE_DEPENDS)
if(HUSK_BUILD_VM)
    set(VM_PACKAGE_ARGUMENTS --vm-runner ${CMAKE_BINARY_DIR}/PackagedVM/VMRunner.app)
    set(VM_PACKAGE_DEPENDS PackageVM)
endif()
add_custom_target(PackageMac ALL
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/package_macos.py
        --app "$<TARGET_BUNDLE_DIR:HuskMac>" --runner "$<TARGET_BUNDLE_DIR:NativeRunner>"
        --deps ${HUSK_DEPS} --fixtures ${FIXTURES} --destination ${HUSK_PRODUCT}
        --java-runtime ${HUSK_JAVA_RUNTIME} ${VM_PACKAGE_ARGUMENTS}
    DEPENDS HuskMac NativeRunner Fixtures JavaRuntimeResources ${VM_PACKAGE_DEPENDS} VERBATIM)

enable_testing()
add_executable(MacCompatibilityTests tests/macos/CommunityCompatibility.swift src/app/Husk/Compatibility.swift)
target_compile_options(MacCompatibilityTests PRIVATE -parse-as-library)
target_link_libraries(MacCompatibilityTests PRIVATE "-framework AppKit" "-framework SwiftUI")
add_test(NAME macos-community-compatibility COMMAND MacCompatibilityTests)
set_tests_properties(macos-community-compatibility PROPERTIES TIMEOUT 30)
add_executable(ManifestGLESTests tests/macos/ManifestGLES.c ${NEXT}/husk-tl-manifest.c)
target_link_libraries(ManifestGLESTests PRIVATE SharedCore)
add_test(NAME java-manifest-gles COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/ManifestGLES.py "$<TARGET_FILE:ManifestGLESTests>")
add_executable(GuestThreadTests tests/macos/GuestThreads.c)
target_link_libraries(GuestThreadTests PRIVATE NativeRuntime)
add_test(NAME java-native-thread-close COMMAND GuestThreadTests)
add_test(NAME java-native-thread-live COMMAND GuestThreadTests live)
set_tests_properties(java-native-thread-close java-native-thread-live PROPERTIES TIMEOUT 10)
add_executable(JavaBootTests tests/macos/JavaBoot.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(JavaBootTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(JavaBootTests PRIVATE NativeRuntime)
add_dependencies(JavaBootTests JavaRuntimeResources)
add_custom_command(TARGET JavaBootTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:JavaBootTests>" VERBATIM)
add_test(NAME java-runtime-boot COMMAND JavaBootTests "${HUSK_JAVA_RUNTIME}" "${CMAKE_BINARY_DIR}/TestResults/JavaBoot")
set_tests_properties(java-runtime-boot PROPERTIES TIMEOUT 60 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=1024")
add_test(NAME java-runtime-resources COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build_java_runtime.py --verify --output ${HUSK_JAVA_RUNTIME})
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_java_case.py "${CMAKE_BINARY_DIR}/JavaTests"
    DEPENDS tests/macos/prepare_java_case.py tests/macos/java/LifecycleActivity.java scripts/build_java_framework.py VERBATIM)
add_custom_target(JavaLifecycleFixture DEPENDS "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk")
add_executable(JavaLifecycleTests tests/macos/JavaLifecycle.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(JavaLifecycleTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(JavaLifecycleTests PRIVATE NativeRuntime)
add_dependencies(JavaLifecycleTests JavaRuntimeResources JavaLifecycleFixture)
add_custom_command(TARGET JavaLifecycleTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:JavaLifecycleTests>" VERBATIM)
foreach(case normal destroy-failed storage-failed live-thread sqlite-uncommitted controller)
    add_test(NAME java-lifecycle-${case} COMMAND JavaLifecycleTests "${HUSK_JAVA_RUNTIME}" "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk"
        "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/JavaLifecycle" ${case})
    set_tests_properties(java-lifecycle-${case} PROPERTIES TIMEOUT 30 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=1024")
endforeach()
add_executable(MacJavaSessionTests tests/macos/JavaSession.swift)
target_compile_options(MacJavaSessionTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacJavaSessionTests PRIVATE SharedLibrary)
add_dependencies(MacJavaSessionTests PackageMac JavaLifecycleFixture)
add_test(NAME macos-java-session COMMAND MacJavaSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk" "${CMAKE_BINARY_DIR}/TestResults")
set_tests_properties(macos-java-session PROPERTIES TIMEOUT 95)
add_test(NAME macos-package-guard COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/PackageGuard.py)
add_executable(VMExitFixture tests/macos/VMExitFixture.m)
target_compile_options(VMExitFixture PRIVATE -fobjc-arc)
target_link_libraries(VMExitFixture PRIVATE "-framework Foundation")
add_executable(VMControllerTests tests/macos/VMControllerTests.swift)
target_compile_options(VMControllerTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(VMControllerTests PRIVATE SharedLibrary)
add_test(NAME macos-vm-controller COMMAND VMControllerTests "$<TARGET_FILE:VMExitFixture>" "${CMAKE_BINARY_DIR}/TestResults")
set_tests_properties(macos-vm-controller PROPERTIES TIMEOUT 25)
if(HUSK_BUILD_VM)
    add_executable(MacVMSession tests/macos/VMSession.swift)
    target_compile_options(MacVMSession PRIVATE -parse-as-library -I ${MAC}/SharedCore)
    target_link_libraries(MacVMSession PRIVATE SharedLibrary)
    add_executable(VMConnectionTests tests/macos/VMConnection.m ${MAC}/VMRunner/VMConnection.m)
    target_include_directories(VMConnectionTests PRIVATE ${MAC}/VMRunner)
    target_compile_options(VMConnectionTests PRIVATE -fobjc-arc -UNDEBUG)
    target_link_libraries(VMConnectionTests PRIVATE "-framework Foundation")
    add_test(NAME vm-bridge-framing COMMAND VMConnectionTests)
endif()
add_executable(JNITextTests tests/macos/JNIText.c)
target_link_libraries(JNITextTests PRIVATE GameActivityRuntime)
add_test(NAME android-jni-text COMMAND JNITextTests)
add_executable(UnityLifecycleTests tests/macos/UnityLifecycle.c)
target_link_libraries(UnityLifecycleTests PRIVATE NativeRuntime)
add_test(NAME unity-lifecycle COMMAND UnityLifecycleTests)
add_test(NAME unity-incomplete-destroy COMMAND UnityLifecycleTests missing-done)
add_test(NAME unity-guest-quit COMMAND UnityLifecycleTests guest-quit)
add_test(NAME unity-modern-player COMMAND UnityLifecycleTests modern-player)
add_test(NAME unity-two-argument-init COMMAND UnityLifecycleTests two-argument-init)
set_tests_properties(unity-lifecycle unity-incomplete-destroy unity-guest-quit unity-modern-player unity-two-argument-init PROPERTIES TIMEOUT 10)
add_executable(AndroidRuntimeTests tests/macos/AndroidRuntime.c)
add_executable(NativeActivityLifecycleTests tests/macos/NativeActivityLifecycle.c)
target_include_directories(NativeActivityLifecycleTests PRIVATE ${CLASSIC})
target_link_libraries(NativeActivityLifecycleTests PRIVATE NativeRuntime)
add_test(NAME nativeactivity-lifecycle COMMAND NativeActivityLifecycleTests)
add_test(NAME nativeactivity-incomplete-destroy COMMAND NativeActivityLifecycleTests missing-destroy)
add_test(NAME nativeactivity-guest-finish COMMAND NativeActivityLifecycleTests guest-finish)
add_test(NAME nativeactivity-create-failed COMMAND NativeActivityLifecycleTests create-failed)
set_tests_properties(nativeactivity-lifecycle nativeactivity-incomplete-destroy nativeactivity-guest-finish nativeactivity-create-failed PROPERTIES TIMEOUT 10)
target_link_libraries(AndroidRuntimeTests PRIVATE NativeRuntime)
add_test(NAME android-runtime-contracts COMMAND AndroidRuntimeTests)
set_tests_properties(android-runtime-contracts PROPERTIES TIMEOUT 10)
add_executable(MacNativeLaunchTests tests/macos/NativeLaunchTests.swift ${MAC}/SharedLibrary/NativeLaunch.swift src/app/Husk/ApkMetadata.swift)
target_compile_options(MacNativeLaunchTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacNativeLaunchTests PRIVATE SharedCore)
add_test(NAME macos-native-launch COMMAND MacNativeLaunchTests)
add_executable(MacTextInputTests tests/macos/TextInput.m ${MAC}/NativeRunner/MacTextInput.m)
target_include_directories(MacTextInputTests PRIVATE ${MAC}/NativeRunner)
target_compile_options(MacTextInputTests PRIVATE -fobjc-arc)
target_link_libraries(MacTextInputTests PRIVATE "-framework AppKit")
add_test(NAME macos-text-input COMMAND MacTextInputTests)
add_executable(MacRenderSurfaceTests tests/macos/RenderSurface.m ${MAC}/NativeRunner/MacRenderView.m
    ${MAC}/NativeRunner/MacTextInput.m ${MAC}/NativeRunner/MacGraphics.m)
target_include_directories(MacRenderSurfaceTests PRIVATE ${MAC}/NativeRunner ${HUSK_DEPS}/include)
target_compile_options(MacRenderSurfaceTests PRIVATE -fobjc-arc)
target_link_libraries(MacRenderSurfaceTests PRIVATE "-framework AppKit" "-framework QuartzCore" "-framework Metal")
add_test(NAME macos-render-surface COMMAND MacRenderSurfaceTests "${HUSK_DEPS}/lib/libANGLE-shared.dylib")
set_tests_properties(macos-render-surface PROPERTIES TIMEOUT 30)
add_executable(MacNativeMouseTests tests/macos/NativeMouse.m ${MAC}/NativeRunner/MacRenderView.m
    ${MAC}/NativeRunner/MacTextInput.m ${MAC}/NativeRunner/MacGraphics.m ${MAC}/NativeRunner/MacAudio.m
    ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacDiagnostics.c ${MAC}/NativeRunner/MacJavaRuntime.m)
target_include_directories(MacNativeMouseTests PRIVATE ${MAC}/NativeRunner ${HUSK_DEPS}/include tests/macos/fixture)
target_compile_options(MacNativeMouseTests PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(MacNativeMouseTests PRIVATE NativeRuntime "-framework AppKit" "-framework QuartzCore"
    "-framework Metal" "-framework Security" "-framework GameController" "-framework AudioToolbox")
add_test(NAME macos-native-mouse COMMAND MacNativeMouseTests)
set_tests_properties(macos-native-mouse PROPERTIES TIMEOUT 15)
add_executable(QuadMathTests tests/macos/QuadMath.c)
target_link_libraries(QuadMathTests PRIVATE GameActivityRuntime)
add_test(NAME android-binary128 COMMAND QuadMathTests)
add_executable(AAudioLifecycleTests tests/macos/AAudioLifecycle.c)
target_link_libraries(AAudioLifecycleTests PRIVATE GameActivityRuntime)
add_test(NAME android-aaudio-lifecycle COMMAND AAudioLifecycleTests)
add_executable(CorePlanTests tests/translation-layer/plan_test.c)
target_include_directories(CorePlanTests PRIVATE ${CLASSIC})
target_link_libraries(CorePlanTests PRIVATE SharedCore)
add_test(NAME core-page-planner COMMAND CorePlanTests)
add_executable(CorePrefsTests tools/prefs-test.c)
target_include_directories(CorePrefsTests PRIVATE ${CLASSIC})
target_link_libraries(CorePrefsTests PRIVATE SharedCore)
add_test(NAME core-prefs COMMAND CorePrefsTests)
add_executable(CoreBlitTests tools/blit-test.c)
target_include_directories(CoreBlitTests PRIVATE ${CLASSIC})
target_link_libraries(CoreBlitTests PRIVATE SharedCore)
add_test(NAME core-blit COMMAND CoreBlitTests)
add_executable(MacHostTests tests/macos/HostTests.m ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacAudio.m)
target_include_directories(MacHostTests PRIVATE ${MAC}/NativeRunner tests/macos/fixture ${HUSK_DEPS}/include)
target_compile_options(MacHostTests PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(MacHostTests PRIVATE "-framework Foundation" "-framework AudioToolbox")
add_test(NAME macos-input-vulkan COMMAND MacHostTests "${HUSK_PRODUCT}/Contents/Frameworks/MoltenVK.framework/MoltenVK")
add_executable(MacSoak tests/macos/Soak.swift)
target_compile_options(MacSoak PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacSoak PRIVATE SharedLibrary)
add_executable(MacCycles tests/macos/Cycles.swift)
target_compile_options(MacCycles PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacCycles PRIVATE SharedLibrary)
add_executable(MacMinecraftSession tests/macos/MinecraftSession.swift)
target_compile_options(MacMinecraftSession PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacMinecraftSession PRIVATE SharedLibrary)
add_executable(MacUnitySession tests/macos/UnitySession.swift)
target_compile_options(MacUnitySession PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacUnitySession PRIVATE SharedLibrary)
if(EXISTS "${CMAKE_SOURCE_DIR}/tests/macos/Integration.swift")
    add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/Cases/ready
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_cases.py ${FIXTURES} ${CMAKE_BINARY_DIR}/Cases
        DEPENDS Fixtures tests/macos/prepare_cases.py VERBATIM)
    add_custom_target(ImportCases DEPENDS ${CMAKE_BINARY_DIR}/Cases/ready)
    add_executable(MacIntegrationTests tests/macos/Integration.swift)
    target_compile_options(MacIntegrationTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
    target_link_libraries(MacIntegrationTests PRIVATE SharedLibrary)
    add_dependencies(MacIntegrationTests PackageMac ImportCases)
    add_test(NAME macos-library-session COMMAND MacIntegrationTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/TestResults" "${CMAKE_BINARY_DIR}/Cases")
    set_tests_properties(macos-library-session PROPERTIES TIMEOUT 120)
    add_executable(MacLibraryCompatibilityTests tests/macos/LibraryCompatibility.swift)
    target_compile_options(MacLibraryCompatibilityTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
    target_link_libraries(MacLibraryCompatibilityTests PRIVATE SharedLibrary)
    add_dependencies(MacLibraryCompatibilityTests PackageMac ImportCases)
    add_test(NAME macos-library-upgrade COMMAND MacLibraryCompatibilityTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/TestResults" "${CMAKE_BINARY_DIR}/Cases")
    set_tests_properties(macos-library-upgrade PROPERTIES TIMEOUT 30)
endif()

add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/PlayCases/ready
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_play_cases.py ${CMAKE_BINARY_DIR}/PlayCases
    DEPENDS tests/macos/prepare_play_cases.py VERBATIM)
add_custom_target(PlayCases DEPENDS ${CMAKE_BINARY_DIR}/PlayCases/ready)
add_executable(MacPlayTests tests/macos/PlaySupport.swift tests/macos/PlayLogin.swift ${MAC_PLAY_SOURCES})
add_dependencies(MacPlayTests PlayCases)
target_compile_options(MacPlayTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacPlayTests PRIVATE SharedLibrary "-framework AppKit")
add_test(NAME macos-play-support COMMAND MacPlayTests ${CMAKE_BINARY_DIR}/PlayCases ${CMAKE_BINARY_DIR}/TestResults)
set_tests_properties(macos-play-support PROPERTIES TIMEOUT 30)
add_executable(APKSplitTests tests/macos/APKSplits.c)
add_dependencies(APKSplitTests PlayCases)
target_compile_options(APKSplitTests PRIVATE -UNDEBUG)
target_link_libraries(APKSplitTests PRIVATE GameActivityRuntime)
add_test(NAME macos-apk-splits COMMAND APKSplitTests ${CMAKE_BINARY_DIR}/PlayCases)
add_executable(VMInstallTests tests/macos/VMInstall.m ${MAC}/VMRunner/VMInstall.m ${MAC}/VMRunner/VMConnection.m)
target_include_directories(VMInstallTests PRIVATE ${MAC}/VMRunner)
target_compile_options(VMInstallTests PRIVATE -fobjc-arc -UNDEBUG)
target_link_libraries(VMInstallTests PRIVATE "-framework Foundation")
add_test(NAME macos-vm-apk-install COMMAND VMInstallTests)
