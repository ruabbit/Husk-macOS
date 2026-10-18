cmake_minimum_required(VERSION 3.28)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Supported native architecture")
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0 CACHE STRING "Provisional deployment floor; requires separate machine validation")
project(HuskMac VERSION 3.0.0 LANGUAGES C OBJC Swift)
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
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build_java_runtime.py --ensure --output ${HUSK_JAVA_RUNTIME}
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
    ${MAC}/SharedLibrary/Models.swift ${MAC}/SharedLibrary/WebStorage.swift ${MAC}/SharedLibrary/AtomicFile.swift ${MAC}/SharedLibrary/APKSignature.swift
    ${MAC}/SharedLibrary/LibraryRepository.swift ${MAC}/SharedLibrary/APKIcon.swift ${MAC}/SharedLibrary/SessionDiagnostics.swift
    ${MAC}/SharedLibrary/SessionController.swift ${MAC}/SharedLibrary/NativeLaunch.swift ${MAC}/SharedLibrary/VMController.swift
    src/app/Husk/ApkMetadata.swift src/app/Husk/BundleUnpacker.swift src/app/Husk/GeodeRelease.swift ${MAC}/SharedLibrary/Geode.swift)
target_link_libraries(SharedLibrary PUBLIC SharedCore "-framework Security" "-framework ImageIO" "-framework UniformTypeIdentifiers")
target_compile_options(SharedLibrary PRIVATE -I ${MAC}/SharedCore -enable-testing)

add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/IconCases/ready
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_icon_cases.py ${CMAKE_BINARY_DIR}/IconCases
    DEPENDS tests/macos/prepare_icon_cases.py VERBATIM)
add_custom_target(IconCases DEPENDS ${CMAKE_BINARY_DIR}/IconCases/ready)
add_executable(MacAPKIconTests tests/macos/APKIcons.swift ${MAC}/SharedLibrary/APKIcon.swift src/app/Husk/ApkMetadata.swift)
target_compile_options(MacAPKIconTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacAPKIconTests PRIVATE SharedLibrary)
add_dependencies(MacAPKIconTests IconCases)
add_test(NAME macos-apk-icons COMMAND MacAPKIconTests ${CMAKE_BINARY_DIR}/IconCases)
add_executable(MacSessionDiagnosticsTests tests/macos/SessionDiagnostics.swift)
target_compile_options(MacSessionDiagnosticsTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacSessionDiagnosticsTests PRIVATE SharedLibrary)
add_test(NAME macos-session-diagnostics COMMAND MacSessionDiagnosticsTests)
set_tests_properties(macos-apk-icons macos-session-diagnostics PROPERTIES TIMEOUT 30)

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
    ${NEXT}/husk-tl-nativeactivity.c ${NEXT}/husk-tl-dvm-nativeactivity.c ${NEXT}/husk-tl-jni-ue4.c
    ${NEXT}/husk-tl-cocos.c ${NEXT}/husk-tl-jni-cocos.c ${NEXT}/husk-tl-cocos-text.c
    ${NEXT}/husk-tl-godot.c ${NEXT}/husk-tl-jni-godot.c ${NEXT}/husk-tl-gamemaker.c
    ${NEXT}/husk-tl-sdl.c ${NEXT}/husk-tl-sdl-apps.c ${NEXT}/husk-tl-gtasa.c
    ${NEXT}/husk-tl-geode.c ${NEXT}/husk-tl-python.c
    ${NEXT}/husk-tl-audio.c ${NEXT}/husk-tl-http.m ${NEXT}/husk-tl-vulkan.m)
target_include_directories(GameActivityRuntime PUBLIC ${NEXT} PRIVATE ${CLASSIC})
target_compile_options(GameActivityRuntime PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(GameActivityRuntime PUBLIC SharedCore resolv sqlite3 "-framework Foundation" "-framework Security"
    "-framework AudioToolbox" "-framework QuartzCore" "-framework Metal" "-framework AppKit"
    "-framework CoreText" "-framework ImageIO" "-framework WebKit" "-framework VideoToolbox"
    "-framework CoreMedia" "-framework CoreVideo" "-framework Accelerate")
add_library(NativeRuntime ALIAS GameActivityRuntime)

# The console ABI is staged independently until the real core's teardown and
# packaging have passed. Test modules are never installed into Product.
add_library(ConsoleHostRuntime STATIC ${NEXT}/husk-console-host.c ${NEXT}/husk-jit-arena.c)
target_include_directories(ConsoleHostRuntime PUBLIC ${NEXT})
target_link_libraries(ConsoleHostRuntime PUBLIC NativeRuntime)
add_executable(MacConsoleProbe tools/ps4-test.m)
target_compile_options(MacConsoleProbe PRIVATE -fobjc-arc)
target_link_libraries(MacConsoleProbe PRIVATE ConsoleHostRuntime)
add_executable(JITArenaTests tools/jit-arena-test.c ${NEXT}/husk-jit-arena.c)
add_library(ConsoleModuleFixture SHARED tests/macos/ConsoleModule.c)
target_include_directories(ConsoleModuleFixture PRIVATE ${NEXT})
add_executable(ConsoleHostTests tests/macos/ConsoleHost.c)
target_link_libraries(ConsoleHostTests PRIVATE ConsoleHostRuntime)
add_dependencies(ConsoleHostTests ConsoleModuleFixture)
foreach(target MacConsoleProbe JITArenaTests ConsoleHostTests)
    add_custom_command(TARGET ${target} POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
        --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:${target}>" VERBATIM)
endforeach()
add_test(NAME console-jit-arena COMMAND JITArenaTests)
set_tests_properties(console-jit-arena PROPERTIES TIMEOUT 15)
foreach(case normal wrong-abi missing-callback stop-pending)
    add_test(NAME console-host-${case} COMMAND ConsoleHostTests "$<TARGET_FILE:ConsoleModuleFixture>" ${case})
    set_tests_properties(console-host-${case} PROPERTIES TIMEOUT 15)
endforeach()

add_executable(MinecraftProbe tests/macos/MinecraftProbe.c)
target_link_libraries(MinecraftProbe PRIVATE GameActivityRuntime)
add_executable(NativeActivityProbe tests/macos/NativeActivityProbe.m ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(NativeActivityProbe PRIVATE ${MAC}/NativeRunner)
target_compile_options(NativeActivityProbe PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(NativeActivityProbe PRIVATE NativeRuntime "-framework Foundation")
add_executable(JavaAppProbe tests/macos/JavaAppProbe.m ${MAC}/NativeRunner/MacJavaRuntime.m ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(JavaAppProbe PRIVATE ${MAC}/NativeRunner)
target_compile_options(JavaAppProbe PRIVATE -fobjc-arc)
target_link_libraries(JavaAppProbe PRIVATE NativeRuntime)
add_dependencies(JavaAppProbe JavaRuntimeResources)
add_custom_command(TARGET JavaAppProbe POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:JavaAppProbe>" VERBATIM)

add_executable(NativeRunner MACOSX_BUNDLE ${MAC}/NativeRunner/main.m ${MAC}/NativeRunner/MacGraphics.m
    ${MAC}/NativeRunner/MacAudio.m ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacDiagnostics.c ${MAC}/NativeRunner/MacJavaRuntime.m ${MAC}/NativeRunner/MacNativeDrivers.m ${MAC}/NativeRunner/MacGeode.m
    ${MAC}/NativeRunner/MacTextInput.m ${MAC}/NativeRunner/MacRenderView.m "${HUSK_ICON}")
add_dependencies(NativeRunner MacIcon)
target_include_directories(NativeRunner PRIVATE ${HUSK_DEPS}/include tests/macos/fixture)
target_compile_options(NativeRunner PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(NativeRunner PRIVATE NativeRuntime "-framework AppKit" "-framework QuartzCore"
    "-framework Metal" "-framework Security" "-framework GameController" "-framework AudioToolbox")
set_target_properties(NativeRunner PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/NativeRunner/Info.plist.in)

add_executable(WebRunner MACOSX_BUNDLE ${MAC}/WebRunner/main.swift ${MAC}/WebRunner/WebLifecycle.swift src/app/Husk/WebApp.swift "${HUSK_ICON}")
add_dependencies(WebRunner MacIcon)
target_compile_options(WebRunner PRIVATE -D HUSK_MAC_WEB -I ${MAC}/SharedCore)
target_link_libraries(WebRunner PRIVATE SharedLibrary "-framework AppKit" "-framework WebKit")
set_target_properties(WebRunner PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/WebRunner/Info.plist.in)

set(MAC_PLAY_SOURCES
    src/app/Husk/Play/Protobuf.swift src/app/Husk/Play/PlayDevice.swift src/app/Husk/Play/PlayAPI.swift
    ${MAC}/Play/GoogleLoginPolicy.swift ${MAC}/Play/GoogleBrowserLogin.swift
    ${MAC}/Play/PlayCredentials.swift ${MAC}/Play/PlayDownload.swift ${MAC}/Play/MacPlayStore.swift)
add_executable(HuskMac MACOSX_BUNDLE ${MAC_PLAY_SOURCES} ${MAC}/Play/PlayStoreView.swift ${MAC}/Play/GoogleLoginView.swift
    ${MAC}/HuskMac/HuskMac.swift ${MAC}/HuskMac/MacShell.swift ${MAC}/HuskMac/MacCompatibility.swift src/app/Husk/Holiday.swift src/app/Husk/Compatibility.swift "${HUSK_ICON}")
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
        --java-runtime ${HUSK_JAVA_RUNTIME} --web-runner "$<TARGET_BUNDLE_DIR:WebRunner>" ${VM_PACKAGE_ARGUMENTS}
    DEPENDS HuskMac NativeRunner WebRunner Fixtures JavaRuntimeResources ${VM_PACKAGE_DEPENDS} VERBATIM)

enable_testing()
add_executable(MacVulkanZeroInitTests tests/macos/VulkanZeroInit.c)
target_include_directories(MacVulkanZeroInitTests PRIVATE ${HUSK_DEPS}/include)
add_test(NAME macos-vulkan-zero-init COMMAND MacVulkanZeroInitTests "${HUSK_PRODUCT}/Contents/Frameworks/MoltenVK.framework/MoltenVK")
add_executable(MacVulkanLoaderTests tests/macos/VulkanLoader.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(MacVulkanLoaderTests PRIVATE ${HUSK_DEPS}/include ${MAC}/NativeRunner)
target_link_libraries(MacVulkanLoaderTests PRIVATE NativeRuntime)
add_test(NAME macos-vulkan-loader COMMAND MacVulkanLoaderTests "${HUSK_PRODUCT}/Contents/Frameworks/MoltenVK.framework/MoltenVK")
add_executable(MacVulkanCompositorTests tests/translation-layer/vulkan_compositor.m ${NEXT}/husk-tl-vulkan.m)
target_include_directories(MacVulkanCompositorTests PRIVATE ${HUSK_DEPS}/include ${NEXT})
target_compile_options(MacVulkanCompositorTests PRIVATE -fobjc-arc)
target_link_libraries(MacVulkanCompositorTests PRIVATE "-framework Foundation" "-framework QuartzCore" "-framework Metal")
add_test(NAME macos-vulkan-compositor COMMAND MacVulkanCompositorTests "${HUSK_PRODUCT}/Contents/Frameworks/MoltenVK.framework/MoltenVK")
add_test(NAME macos-vulkan-compositor-same-queue COMMAND MacVulkanCompositorTests "${HUSK_PRODUCT}/Contents/Frameworks/MoltenVK.framework/MoltenVK" --same-queue)
set_tests_properties(macos-vulkan-compositor macos-vulkan-compositor-same-queue PROPERTIES TIMEOUT 30 ENVIRONMENT "MVK_CONFIG_LOG_LEVEL=1")
set_tests_properties(macos-vulkan-zero-init PROPERTIES TIMEOUT 30 ENVIRONMENT "MVK_CONFIG_LOG_LEVEL=1")
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/WebTests/capacitor.apk" "${CMAKE_BINARY_DIR}/WebTests/cordova.apk"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_web_cases.py "${CMAKE_BINARY_DIR}/WebTests" "${CMAKE_BINARY_DIR}/NativeTests/godot.apk"
    DEPENDS tests/macos/prepare_web_cases.py NativeDriverFixtures "${CMAKE_BINARY_DIR}/NativeTests/godot.apk" VERBATIM)
add_custom_target(WebFixtures DEPENDS "${CMAKE_BINARY_DIR}/WebTests/capacitor.apk" "${CMAKE_BINARY_DIR}/WebTests/cordova.apk")
add_executable(MacWebSessionTests tests/macos/WebSession.swift)
target_compile_options(MacWebSessionTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacWebSessionTests PRIVATE SharedLibrary)
add_dependencies(MacWebSessionTests PackageMac WebFixtures)
foreach(kind capacitor cordova)
    add_test(NAME macos-web-${kind} COMMAND MacWebSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/WebTests/${kind}.apk" ${kind} "${CMAKE_BINARY_DIR}/TestResults")
    set_tests_properties(macos-web-${kind} PROPERTIES TIMEOUT 150)
endforeach()
add_executable(MacNativeDriverSessionTests tests/macos/NativeDriverSession.swift)
target_compile_options(MacNativeDriverSessionTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacNativeDriverSessionTests PRIVATE SharedLibrary)
add_dependencies(MacNativeDriverSessionTests PackageMac NativeDriverFixtures)
foreach(engine cocos godot gamemaker sdl gta ue4)
    add_test(NAME macos-${engine}-session COMMAND MacNativeDriverSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/NativeTests/${engine}.apk" ${engine} "${CMAKE_BINARY_DIR}/TestResults")
    set_tests_properties(macos-${engine}-session PROPERTIES TIMEOUT 60)
endforeach()
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/NativeTests/gamemaker.apk" "${CMAKE_BINARY_DIR}/NativeTests/godot.apk" "${CMAKE_BINARY_DIR}/NativeTests/cocos.apk"
    "${CMAKE_BINARY_DIR}/NativeTests/gamemaker-missing.apk" "${CMAKE_BINARY_DIR}/NativeTests/godot-missing.apk"
    "${CMAKE_BINARY_DIR}/NativeTests/sdl.apk" "${CMAKE_BINARY_DIR}/NativeTests/gta.apk"
    "${CMAKE_BINARY_DIR}/NativeTests/ue4.apk"
    "${CMAKE_BINARY_DIR}/NativeTests/godot-pause-failed.apk" "${CMAKE_BINARY_DIR}/NativeTests/godot-godot4.apk"
    "${CMAKE_BINARY_DIR}/NativeTests/sdl-missing.apk" "${CMAKE_BINARY_DIR}/NativeTests/gta-missing.apk"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_native_cases.py "${CMAKE_BINARY_DIR}/NativeTests"
    DEPENDS tests/macos/prepare_native_cases.py tests/macos/fixture/native_driver.c scripts/build_macos_fixture.py VERBATIM)
add_custom_target(NativeDriverFixtures DEPENDS "${CMAKE_BINARY_DIR}/NativeTests/gamemaker.apk" "${CMAKE_BINARY_DIR}/NativeTests/godot.apk" "${CMAKE_BINARY_DIR}/NativeTests/cocos.apk")
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/GeodeTests/ready"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_geode_cases.py "${CMAKE_BINARY_DIR}/GeodeTests" "${CMAKE_BINARY_DIR}/NativeTests"
    DEPENDS tests/macos/prepare_geode_cases.py tests/macos/fixture/geode.c NativeDriverFixtures "${CMAKE_BINARY_DIR}/NativeTests/cocos.apk" VERBATIM)
add_custom_target(GeodeFixtures DEPENDS "${CMAKE_BINARY_DIR}/GeodeTests/ready")
add_executable(MacGeodeTests tests/macos/Geode.swift)
target_compile_options(MacGeodeTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacGeodeTests PRIVATE SharedLibrary)
add_dependencies(MacGeodeTests GeodeFixtures)
add_test(NAME macos-geode-cache COMMAND MacGeodeTests "${CMAKE_BINARY_DIR}/GeodeTests")
set_tests_properties(macos-geode-cache PROPERTIES TIMEOUT 30)
add_executable(GeodeLifecycleTests tests/macos/GeodeLifecycle.m ${MAC}/NativeRunner/MacGeode.m ${MAC}/NativeRunner/MacNativeDrivers.m ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(GeodeLifecycleTests PRIVATE ${MAC}/NativeRunner)
target_compile_options(GeodeLifecycleTests PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(GeodeLifecycleTests PRIVATE NativeRuntime)
add_dependencies(GeodeLifecycleTests GeodeFixtures)
add_custom_command(TARGET GeodeLifecycleTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:GeodeLifecycleTests>" VERBATIM)
foreach(mode normal jni-error)
    set(outcome success)
    if(mode STREQUAL "jni-error")
        set(outcome failure)
    endif()
    add_test(NAME native-geode-${mode} COMMAND GeodeLifecycleTests "${CMAKE_BINARY_DIR}/GeodeTests/${mode}"
        "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/Geode" ${outcome})
    set_tests_properties(native-geode-${mode} PROPERTIES TIMEOUT 20 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=128")
endforeach()
add_dependencies(MacNativeDriverSessionTests GeodeFixtures)
add_test(NAME macos-geode-session COMMAND MacNativeDriverSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/GeodeTests/normal/game.apk" geode "${CMAKE_BINARY_DIR}/TestResults")
set_tests_properties(macos-geode-session PROPERTIES TIMEOUT 60)
add_executable(NativeDriverLifecycleTests tests/macos/NativeDriverLifecycle.m ${MAC}/NativeRunner/MacNativeDrivers.m ${MAC}/NativeRunner/MacDiagnostics.c)
target_compile_options(NativeDriverLifecycleTests PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_include_directories(NativeDriverLifecycleTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(NativeDriverLifecycleTests PRIVATE NativeRuntime)
add_dependencies(NativeDriverLifecycleTests NativeDriverFixtures)
add_custom_command(TARGET NativeDriverLifecycleTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:NativeDriverLifecycleTests>" VERBATIM)
add_test(NAME native-driver-failure-sticky COMMAND NativeDriverLifecycleTests godot "${CMAKE_BINARY_DIR}/NativeTests/godot-pause-failed.apk"
    "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/NativeDrivers")
set_tests_properties(native-driver-failure-sticky PROPERTIES TIMEOUT 20 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=128")
foreach(engine cocos godot gamemaker sdl gta)
    add_test(NAME native-${engine}-lifecycle COMMAND NativeDriverLifecycleTests ${engine} "${CMAKE_BINARY_DIR}/NativeTests/${engine}.apk"
        "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/NativeDrivers")
    set_tests_properties(native-${engine}-lifecycle PROPERTIES TIMEOUT 20 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=128")
endforeach()
foreach(engine godot gamemaker sdl gta)
    add_test(NAME native-${engine}-missing-destroy COMMAND NativeDriverLifecycleTests ${engine} "${CMAKE_BINARY_DIR}/NativeTests/${engine}-missing.apk"
        "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/NativeDrivers")
    set_tests_properties(native-${engine}-missing-destroy PROPERTIES TIMEOUT 20 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=128")
endforeach()
add_executable(MacCompatibilityTests tests/macos/CommunityCompatibility.swift src/app/Husk/Compatibility.swift)
foreach(mode compatibility explicit-vulkan)
    add_test(NAME native-godot4-${mode} COMMAND NativeDriverLifecycleTests godot "${CMAKE_BINARY_DIR}/NativeTests/godot-godot4.apk"
        "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/NativeDrivers")
    set_tests_properties(native-godot4-${mode} PROPERTIES TIMEOUT 20 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=128")
endforeach()
set_property(TEST native-godot4-explicit-vulkan APPEND PROPERTY ENVIRONMENT "TL_GODOT_VULKAN=1")
add_executable(ExternalTextureShaderTests tests/macos/ExternalTextureShader.c)
target_include_directories(ExternalTextureShaderTests PRIVATE ${HUSK_DEPS}/include)
target_link_libraries(ExternalTextureShaderTests PRIVATE NativeRuntime)
add_test(NAME macos-external-texture-shader COMMAND ExternalTextureShaderTests "${HUSK_DEPS}/lib/libANGLE-shared.dylib")
set_tests_properties(macos-external-texture-shader PROPERTIES TIMEOUT 30)
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
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/LoaderTests/ready"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_loader_cases.py "${CMAKE_BINARY_DIR}/LoaderTests"
    DEPENDS tests/macos/prepare_loader_cases.py tests/macos/fixture/namespace.c tests/macos/fixture/data_views.S scripts/build_macos_fixture.py VERBATIM)
add_custom_target(LoaderFixtures DEPENDS "${CMAKE_BINARY_DIR}/LoaderTests/ready")
add_executable(LoaderDataViewTests tests/macos/LoaderDataViews.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(LoaderDataViewTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(LoaderDataViewTests PRIVATE NativeRuntime)
add_dependencies(LoaderDataViewTests LoaderFixtures)
add_custom_command(TARGET LoaderDataViewTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:LoaderDataViewTests>" VERBATIM)
foreach(mode go-data mixed-data go-mixed-data)
    add_test(NAME core-loader-${mode} COMMAND LoaderDataViewTests "${CMAKE_BINARY_DIR}/LoaderTests/${mode}.so")
    set_tests_properties(core-loader-${mode} PROPERTIES TIMEOUT 15 ENVIRONMENT "TL_XMEM_MIB=64")
endforeach()
add_executable(LoaderNamespaceTests tests/macos/LoaderNamespace.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(LoaderNamespaceTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(LoaderNamespaceTests PRIVATE NativeRuntime)
add_dependencies(LoaderNamespaceTests LoaderFixtures)
add_custom_command(TARGET LoaderNamespaceTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:LoaderNamespaceTests>" VERBATIM)
foreach(mode apk-first apk-system-first unpacked-first unpacked-system-first)
    add_test(NAME core-loader-namespace-${mode} COMMAND LoaderNamespaceTests "${CMAKE_BINARY_DIR}/LoaderTests" ${mode})
    set_tests_properties(core-loader-namespace-${mode} PROPERTIES TIMEOUT 15 ENVIRONMENT "TL_XMEM_MIB=64")
endforeach()
add_dependencies(JavaBootTests LoaderFixtures)
foreach(order app-first system-first)
    add_test(NAME java-runtime-crypto-${order} COMMAND JavaBootTests "${HUSK_JAVA_RUNTIME}"
        "${CMAKE_BINARY_DIR}/TestResults/JavaBoot-${order}" "${CMAKE_BINARY_DIR}/LoaderTests/app.apk" ${order})
    set_tests_properties(java-runtime-crypto-${order} PROPERTIES TIMEOUT 60 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=1024")
endforeach()
add_executable(MacSystemResourceTests tests/macos/SystemResources.m ${MAC}/NativeRunner/MacJavaRuntime.m ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(MacSystemResourceTests PRIVATE ${MAC}/NativeRunner)
target_compile_options(MacSystemResourceTests PRIVATE -fobjc-arc)
target_link_libraries(MacSystemResourceTests PRIVATE NativeRuntime)
add_dependencies(MacSystemResourceTests JavaRuntimeResources)
add_test(NAME macos-system-resources COMMAND MacSystemResourceTests ${HUSK_JAVA_RUNTIME})
set_tests_properties(macos-system-resources PROPERTIES TIMEOUT 30)
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_java_case.py "${CMAKE_BINARY_DIR}/JavaTests"
    DEPENDS tests/macos/prepare_java_case.py tests/macos/java/LifecycleActivity.java tests/macos/java/FrameworkChecks.java tests/macos/java/MissingOptional.java tests/macos/java/unicode/例.java scripts/build_java_framework.py VERBATIM)
add_custom_target(JavaLifecycleFixture DEPENDS "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk")
add_executable(JavaLifecycleTests tests/macos/JavaLifecycle.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(JavaLifecycleTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(JavaLifecycleTests PRIVATE NativeRuntime)
add_dependencies(JavaLifecycleTests JavaRuntimeResources JavaLifecycleFixture)
add_custom_command(TARGET JavaLifecycleTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:JavaLifecycleTests>" VERBATIM)
foreach(case normal destroy-failed storage-failed live-thread sqlite-uncommitted controller preferences-idle framework)
    add_test(NAME java-lifecycle-${case} COMMAND JavaLifecycleTests "${HUSK_JAVA_RUNTIME}" "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk"
        "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/JavaLifecycle" ${case})
    set_tests_properties(java-lifecycle-${case} PROPERTIES TIMEOUT 30 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=1024")
endforeach()
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/KeyStoreTests/KeyStore.apk"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_java_case.py "${CMAKE_BINARY_DIR}/KeyStoreTests" keystore
    DEPENDS tests/macos/prepare_java_case.py tests/macos/java/KeyStoreActivity.java scripts/build_java_framework.py VERBATIM)
add_custom_target(JavaKeyStoreFixture DEPENDS "${CMAKE_BINARY_DIR}/KeyStoreTests/KeyStore.apk")
add_executable(JavaKeyStoreTests tests/macos/JavaKeyStore.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(JavaKeyStoreTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(JavaKeyStoreTests PRIVATE NativeRuntime)
add_dependencies(JavaKeyStoreTests JavaRuntimeResources JavaKeyStoreFixture)
add_custom_command(TARGET JavaKeyStoreTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:JavaKeyStoreTests>" VERBATIM)
add_test(NAME java-keystore-import-persistence COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/JavaKeyStore.py
    "$<TARGET_FILE:JavaKeyStoreTests>" "${HUSK_JAVA_RUNTIME}" "${CMAKE_BINARY_DIR}/KeyStoreTests/KeyStore.apk"
    "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/KeyStore")
set_tests_properties(java-keystore-import-persistence PROPERTIES TIMEOUT 180)
add_executable(MacJavaSessionTests tests/macos/JavaSession.swift)
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/NativeBootstrap/Startup.apk" "${CMAKE_BINARY_DIR}/NativeBootstrap/split.apk" "${CMAKE_BINARY_DIR}/NativeBootstrap/Startup.apks"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_native_bootstrap.py "${CMAKE_BINARY_DIR}/NativeBootstrap"
    DEPENDS tests/macos/prepare_native_bootstrap.py tests/macos/java/nativeactivity/Bootstrap.java tests/macos/java/nativeactivity/Provider.java tests/macos/java/nativeactivity/Factory.java
        tests/macos/java/nativeactivity/Game.java tests/macos/fixture/native_bootstrap.c tests/macos/fixture/java_nativeactivity.c
        ${NEXT}/husk-tl-nativeactivity-abi.h VERBATIM)
add_custom_target(NativeBootstrapFixture DEPENDS "${CMAKE_BINARY_DIR}/NativeBootstrap/Startup.apk" "${CMAKE_BINARY_DIR}/NativeBootstrap/split.apk" "${CMAKE_BINARY_DIR}/NativeBootstrap/Startup.apks")
add_executable(JavaNativeActivityTests tests/macos/JavaNativeActivity.c ${MAC}/NativeRunner/MacDiagnostics.c)
target_include_directories(JavaNativeActivityTests PRIVATE ${MAC}/NativeRunner)
target_link_libraries(JavaNativeActivityTests PRIVATE NativeRuntime)
add_dependencies(JavaNativeActivityTests JavaRuntimeResources NativeBootstrapFixture)
add_custom_command(TARGET JavaNativeActivityTests POST_BUILD COMMAND codesign --force --sign - --timestamp=none --options runtime
    --entitlements ${MAC}/NativeRunner/NativeRunner.development.entitlements "$<TARGET_FILE:JavaNativeActivityTests>" VERBATIM)
foreach(case normal guest-finish missing-destroy native-create-failed java-create-failed)
    add_test(NAME java-nativeactivity-${case} COMMAND JavaNativeActivityTests "${HUSK_JAVA_RUNTIME}" "${CMAKE_BINARY_DIR}/NativeBootstrap/Startup.apk"
        "${CMAKE_BINARY_DIR}/NativeBootstrap/split.apk" "${HUSK_DEPS}/lib/libANGLE-shared.dylib" "${CMAKE_BINARY_DIR}/TestResults/NativeBootstrap" ${case})
    set_tests_properties(java-nativeactivity-${case} PROPERTIES TIMEOUT 30 ENVIRONMENT "TL_AUDIO_MUTE=1;TL_XMEM_MIB=1024")
endforeach()
target_compile_options(MacJavaSessionTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacJavaSessionTests PRIVATE SharedLibrary)
add_dependencies(MacJavaSessionTests PackageMac JavaLifecycleFixture NativeBootstrapFixture)
add_test(NAME macos-java-session COMMAND MacJavaSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/JavaTests/Lifecycle.apk" "${CMAKE_BINARY_DIR}/TestResults")
set_tests_properties(macos-java-session PROPERTIES TIMEOUT 95)
add_test(NAME macos-java-nativeactivity-session COMMAND MacJavaSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/NativeBootstrap/Startup.apks" "${CMAKE_BINARY_DIR}/TestResults" nativeactivity)
set_tests_properties(macos-java-nativeactivity-session PROPERTIES TIMEOUT 95)
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/JavaWebTests/WebStorage.apk"
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/macos/prepare_java_case.py "${CMAKE_BINARY_DIR}/JavaWebTests" web
    DEPENDS tests/macos/prepare_java_case.py tests/macos/java/WebStorageActivity.java tests/macos/java/storage.html scripts/build_java_framework.py VERBATIM)
add_custom_target(JavaWebFixture DEPENDS "${CMAKE_BINARY_DIR}/JavaWebTests/WebStorage.apk")
add_executable(MacJavaWebSessionTests tests/macos/JavaWebSession.swift)
target_compile_options(MacJavaWebSessionTests PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(MacJavaWebSessionTests PRIVATE SharedLibrary)
add_dependencies(MacJavaWebSessionTests PackageMac JavaWebFixture)
foreach(case persistence legacy destroy-failed identity late-bridge)
    add_test(NAME macos-java-web-${case} COMMAND MacJavaWebSessionTests "${HUSK_PRODUCT}" "${CMAKE_BINARY_DIR}/JavaWebTests/WebStorage.apk" "${CMAKE_BINARY_DIR}/TestResults" ${case})
    set_tests_properties(macos-java-web-${case} PROPERTIES TIMEOUT 180)
endforeach()
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
add_executable(OpenSLLifecycleTests tests/macos/OpenSLLifecycle.c)
target_link_libraries(OpenSLLifecycleTests PRIVATE NativeRuntime)
add_test(NAME opensl-lifecycle COMMAND OpenSLLifecycleTests)
set_tests_properties(opensl-lifecycle PROPERTIES TIMEOUT 10)
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
    ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacDiagnostics.c ${MAC}/NativeRunner/MacJavaRuntime.m ${MAC}/NativeRunner/MacNativeDrivers.m ${MAC}/NativeRunner/MacGeode.m)
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
