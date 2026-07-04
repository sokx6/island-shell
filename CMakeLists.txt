cmake_minimum_required(VERSION 3.16)
project(HyprlandCustom VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Network DBus Concurrent)
find_library(UDEV_LIB NAMES udev REQUIRED)

# Lyrics daemon (MPRIS watcher + online lyrics fetcher)
add_executable(lyricsmpris
    lyricsmpris/main.cpp
    lyricsmpris/CjkVariantNormalizer.h
    lyricsmpris/CjkVariantNormalizer.cpp
    lyricsmpris/LyricsCore.h
    lyricsmpris/LyricsCore.cpp
    lyricsmpris/LyricsMprisApp.h
    lyricsmpris/LyricsMprisApp.cpp
)

target_include_directories(lyricsmpris PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/lyricsmpris
)

target_link_libraries(lyricsmpris PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::DBus
)

# Main Backend Module (QML singletons exposed to QML via IslandBackend URI)
qt_add_qml_module(IslandBackend
    URI IslandBackend
    VERSION 1.0
    SOURCES
        backend/SysBackend.h
        backend/SysBackend.cpp
        backend/SystemServices.h
        backend/SystemServices.cpp
        backend/StyleTokensBackend.h
        backend/StyleTokensBackend.cpp
        backend/UserConfigBackend.h
        backend/UserConfigBackend.cpp
        backend/BluetoothPairingAgent.h
        backend/BluetoothPairingAgent.cpp
        backend/WifiController.h
        backend/WifiController.cpp
        backend/WifiNetworkModel.h
        backend/WifiNetworkModel.cpp
)

target_include_directories(IslandBackend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/backend
)

target_link_libraries(IslandBackend PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Network
    Qt6::DBus
    Qt6::Concurrent
    ${UDEV_LIB}
)

# Installation Rules
# Install to /usr (not /usr/local) so Qt finds IslandBackend in its default QML import path
include(GNUInstallDirs)

# Install IslandBackend backing library to /usr/lib
install(TARGETS IslandBackend
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

# Install IslandBackend plugin to Qt6 QML directory
install(TARGETS IslandBackendplugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/IslandBackend
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install qmldir and generated qmltypes
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/qmldir
    ${CMAKE_CURRENT_BINARY_DIR}/IslandBackend.qmltypes
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/IslandBackend
)

# Install lyricsmpris helper
install(TARGETS lyricsmpris
    RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/IslandBackend/bin
)
