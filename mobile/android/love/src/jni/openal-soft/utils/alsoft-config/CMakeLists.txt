project(alsoft-config)

if(Qt5Widgets_FOUND)
    qt5_wrap_ui(UIS  mainwindow.ui)

    qt5_wrap_cpp(MOCS  mainwindow.h)

    add_executable(alsoft-config
        main.cpp
        mainwindow.cpp
        mainwindow.h
        verstr.cpp
        verstr.h
        ${UIS} ${RSCS} ${TRS} ${MOCS})
    target_link_libraries(alsoft-config PUBLIC Qt5::Widgets PRIVATE alsoft.common)
    target_include_directories(alsoft-config PRIVATE "${alsoft-config_BINARY_DIR}"
        "${OpenAL_BINARY_DIR}")
    target_compile_definitions(alsoft-config PRIVATE QT_NO_KEYWORDS)
    set_target_properties(alsoft-config PROPERTIES ${DEFAULT_TARGET_PROPS}
        RUNTIME_OUTPUT_DIRECTORY ${OpenAL_BINARY_DIR})
    if(TARGET alsoft.build_version)
        add_dependencies(alsoft-config alsoft.build_version)
    endif()

    message(STATUS "Building configuration program")

    if(ALSOFT_INSTALL_UTILS)
        install(TARGETS alsoft-config
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
    endif()
endif()
