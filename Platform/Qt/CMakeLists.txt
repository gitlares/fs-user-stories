cmake_minimum_required(VERSION 3.21)

project(FSUserStoriesQt
    VERSION 1.0.4
    DESCRIPTION "FS User Stories — Linux/Qt front-end"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

option(FS_USER_STORIES_BUILD_TESTS "Build C++ unit tests" OFF)

include(FetchContent)
set(BUILD_WITH_QT6 ON CACHE BOOL "Build QtKeychain with Qt 6" FORCE)
set(BUILD_TEST_APPLICATION OFF CACHE BOOL "Disable QtKeychain test app" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "Disable dependency tests" FORCE)
set(BUILD_TRANSLATIONS OFF CACHE BOOL "Disable QtKeychain translations" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Link QtKeychain statically" FORCE)
set(LIBSECRET_SUPPORT OFF CACHE BOOL "Use Secret Service through Qt D-Bus" FORCE)
FetchContent_Declare(qtkeychain
    GIT_REPOSITORY https://github.com/frankosterfeld/qtkeychain.git
    GIT_TAG ad7344c45a86a4f66cbafc4b081b5f7b876cb0b7
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(qtkeychain)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Widgets
)

qt_standard_project_setup(REQUIRES 6.5)

set(FS_USER_STORIES_SOURCES
    src/main.cpp
    src/CoreClient.h
    src/CoreClient.cpp
    src/CorePaths.h
    src/CorePaths.cpp
    src/CredentialStore.h
    src/CredentialStore.cpp
    src/WorkspaceController.h
    src/WorkspaceController.cpp
    src/StoryModel.h
    src/StoryModel.cpp
    src/AppInfo.h
    src/AppInfo.cpp
)

qt_add_executable(FSUserStories ${FS_USER_STORIES_SOURCES})

if(WIN32)
    enable_language(RC)
    target_sources(FSUserStories PRIVATE resources/windows-icon.rc)
endif()

set_target_properties(FSUserStories PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE FALSE
    OUTPUT_NAME "fs-user-stories"
)

qt_add_qml_module(FSUserStories
    URI FSUserStories
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
        src/qml/WelcomeView.qml
        src/qml/WorkspaceView.qml
        src/qml/StoryList.qml
        src/qml/StoryDetailView.qml
        src/qml/ProjectProfilesView.qml
        src/qml/ProfileDetailView.qml
        src/qml/GitSyncView.qml
        src/qml/Theme.qml
        src/qml/MacButton.qml
        src/qml/MacIconButton.qml
        src/qml/MacTextField.qml
        src/qml/MacComboBox.qml
        src/qml/MacProgressBar.qml
    RESOURCES
        resources/fs-user-stories.desktop
        resources/fonts/MaterialSymbolsOutlined-Variable.ttf
        resources/fonts/InterVariable.ttf
)

target_link_libraries(FSUserStories PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    qt6keychain
)

target_compile_definitions(FSUserStories PRIVATE QTKEYCHAIN_NO_EXPORT)

# Bundle Material Symbols Outlined icon font alongside the binary. main.cpp
# loads it at startup so QML can use icon ligatures (e.g. "person_badge_plus")
# in place of SF Symbol names.
add_custom_command(TARGET FSUserStories POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:FSUserStories>/resources/fonts"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/fonts/MaterialSymbolsOutlined-Variable.ttf"
            "$<TARGET_FILE_DIR:FSUserStories>/resources/fonts/"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/fonts/InterVariable.ttf"
            "$<TARGET_FILE_DIR:FSUserStories>/resources/fonts/"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/../../Design/AppIcon-master.png"
            "$<TARGET_FILE_DIR:FSUserStories>/resources/app-icon.png"
)

target_include_directories(FSUserStories PRIVATE src)

if(FS_USER_STORIES_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

install(TARGETS FSUserStories
    RUNTIME DESTINATION bin
    BUNDLE DESTINATION .
)

install(FILES resources/fs-user-stories.desktop
    DESTINATION share/applications
)

install(DIRECTORY qml DESTINATION share/fs-user-stories)
