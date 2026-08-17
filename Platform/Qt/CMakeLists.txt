cmake_minimum_required(VERSION 3.21)

project(FSUserStoriesQt
    VERSION 0.1.0
    DESCRIPTION "FS User Stories — Linux/Qt front-end"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

option(FS_USER_STORIES_BUILD_TESTS "Build C++ unit tests" OFF)

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
    src/WorkspaceController.h
    src/WorkspaceController.cpp
    src/StoryModel.h
    src/StoryModel.cpp
    src/AppInfo.h
    src/AppInfo.cpp
)

qt_add_executable(FSUserStories ${FS_USER_STORIES_SOURCES})

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
        src/qml/GitSyncView.qml
    RESOURCES
        resources/fs-user-stories.desktop
        resources/fonts/MaterialSymbolsOutlined-Variable.woff2
)

target_link_libraries(FSUserStories PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
)

# Bundle Material Symbols Outlined icon font alongside the binary. main.cpp
# loads it at startup so QML can use icon ligatures (e.g. "person_badge_plus")
# in place of SF Symbol names.
add_custom_command(TARGET FSUserStories POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "$<TARGET_FILE_DIR:FSUserStories>/resources/fonts"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/resources/fonts/MaterialSymbolsOutlined-Variable.ttf"
            "$<TARGET_FILE_DIR:FSUserStories>/resources/fonts/"
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
