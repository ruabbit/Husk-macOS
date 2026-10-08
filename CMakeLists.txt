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
add_library(SharedCore STATIC
    ${CLASSIC}/husk-tl-scan.c ${CLASSIC}/husk-tl-zip.c ${CLASSIC}/husk-tl-elf.c
    ${CLASSIC}/husk-tl-json.c ${CLASSIC}/husk-tl-prefs.c ${CLASSIC}/husk-tl-blit.c
    ${MAC}/SharedCore/Archive.c)
target_include_directories(SharedCore PUBLIC ${MAC}/SharedCore PRIVATE ${CLASSIC})
target_link_libraries(SharedCore PUBLIC z "-framework CoreGraphics")

add_library(SharedLibrary STATIC
    ${MAC}/SharedLibrary/Models.swift ${MAC}/SharedLibrary/AtomicFile.swift
    ${MAC}/SharedLibrary/LibraryRepository.swift ${MAC}/SharedLibrary/SessionController.swift ${MAC}/SharedLibrary/VMController.swift
    src/app/Husk/ApkMetadata.swift src/app/Husk/BundleUnpacker.swift)
target_link_libraries(SharedLibrary PUBLIC SharedCore)
target_compile_options(SharedLibrary PRIVATE -I ${MAC}/SharedCore)

add_library(GameActivityRuntime STATIC
    ${NEXT}/husk-tl-ld.c ${NEXT}/husk-tl-a64.c ${NEXT}/husk-tl-xmem.c ${NEXT}/husk-tl-va.c ${NEXT}/husk-tl-codewrite.c
    ${NEXT}/husk-tl-bionic.c ${NEXT}/husk-tl-bionic-str.c ${NEXT}/husk-tl-bionic-io.c
    ${NEXT}/husk-tl-bionic-net.c ${NEXT}/husk-tl-bionic-pthread.c ${NEXT}/husk-tl-bionic-cxx.c
    ${NEXT}/husk-tl-bionic-ndk.c ${NEXT}/husk-tl-opensles.c
    ${NEXT}/husk-tl-jni.c ${NEXT}/husk-tl-jni-hle.c ${NEXT}/husk-tl-jni-loop.c
    ${NEXT}/husk-tl-jni-input.c ${NEXT}/husk-tl-jni-assetstream.c ${NEXT}/husk-tl-jni-tls.c
    ${NEXT}/husk-tl-jni-http.c ${NEXT}/husk-tl-jni-security.c ${NEXT}/husk-tl-jni-fmod.c ${NEXT}/husk-tl-jni-gms.c
    ${NEXT}/husk-tl-jni-minecraft.c ${NEXT}/husk-tl-jni-text.c ${NEXT}/husk-tl-dexindex.c
    ${NEXT}/husk-tl-egl.c ${NEXT}/husk-tl-gameactivity.c ${NEXT}/husk-tl-gamepad.c
    ${NEXT}/husk-tl-audio.c ${NEXT}/husk-tl-http.m ${NEXT}/husk-tl-vulkan.m)
target_include_directories(GameActivityRuntime PUBLIC ${NEXT} PRIVATE ${CLASSIC})
target_compile_options(GameActivityRuntime PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(GameActivityRuntime PUBLIC SharedCore resolv "-framework Foundation" "-framework Security"
    "-framework AudioToolbox" "-framework QuartzCore" "-framework Metal")
add_library(NativeRuntime ALIAS GameActivityRuntime)

add_executable(MinecraftProbe tests/macos/MinecraftProbe.c)
target_link_libraries(MinecraftProbe PRIVATE GameActivityRuntime)

add_executable(NativeRunner MACOSX_BUNDLE ${MAC}/NativeRunner/main.m ${MAC}/NativeRunner/MacGraphics.m
    ${MAC}/NativeRunner/MacAudio.m ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacDiagnostics.c
    ${MAC}/NativeRunner/MacTextInput.m ${MAC}/NativeRunner/MacRenderView.m)
target_include_directories(NativeRunner PRIVATE ${HUSK_DEPS}/include tests/macos/fixture)
target_compile_options(NativeRunner PRIVATE "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(NativeRunner PRIVATE NativeRuntime "-framework AppKit" "-framework QuartzCore"
    "-framework Metal" "-framework Security" "-framework GameController" "-framework AudioToolbox")
set_target_properties(NativeRunner PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/NativeRunner/Info.plist.in)

add_executable(HuskMac MACOSX_BUNDLE ${MAC}/HuskMac/HuskMac.swift)
target_compile_options(HuskMac PRIVATE -parse-as-library -I ${MAC}/SharedCore)
target_link_libraries(HuskMac PRIVATE SharedLibrary "-framework AppKit" "-framework SwiftUI")
set_target_properties(HuskMac PROPERTIES MACOSX_BUNDLE_INFO_PLIST ${MAC}/HuskMac/Info.plist.in)

if(HUSK_BUILD_VM)
    if(NOT EXISTS "${HUSK_VM_DEPS}/lib/libqemu-aarch64-softmmu.dylib")
        message(FATAL_ERROR "Run python3 scripts/build_macos_vm.py before enabling HUSK_BUILD_VM")
    endif()
    add_executable(VMRunner MACOSX_BUNDLE ${MAC}/VMRunner/main.m ${MAC}/VMRunner/VMDisplay.m
        ${MAC}/VMRunner/VMConnection.m ${MAC}/NativeRunner/MacAudio.m)
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
        --deps ${HUSK_DEPS} --fixtures ${FIXTURES} --destination ${HUSK_PRODUCT} ${VM_PACKAGE_ARGUMENTS}
    DEPENDS HuskMac NativeRunner Fixtures ${VM_PACKAGE_DEPENDS} VERBATIM)

enable_testing()
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
    ${MAC}/NativeRunner/MacInput.c ${MAC}/NativeRunner/MacDiagnostics.c)
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
