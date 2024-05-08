set(MINIOB_CLANG_SEARCH_PATH "/usr/local/bin" "/usr/bin" "/usr/local/opt/llvm/bin" "/usr/local/opt/llvm@10/bin")
# set(CHECK_CLANG_TIDY_REGEX "'.*'") # default all files
set(CHECK_CLANG_TIDY_REGEX "'.*/src/observer/\(sql\)/.*?/\(?!\(lex|yacc\)\).*cpp'")

######################################################################################################################
# DEPENDENCIES
######################################################################################################################

# clang-format
if (NOT DEFINED CLANG_FORMAT_BIN)
    # attempt to find the binary if user did not specify
    find_program(CLANG_FORMAT_BIN
            NAMES clang-format clang-format-10
            HINTS ${MINIOB_CLANG_SEARCH_PATH})
endif()
if ("${CLANG_FORMAT_BIN}" STREQUAL "CLANG_FORMAT_BIN-NOTFOUND")
    message(WARNING "MiniOB couldn't find clang-format.")
else()
    message(STATUS "MiniOB found clang-format at ${CLANG_FORMAT_BIN}")
endif()

# clang-tidy
if (NOT DEFINED CLANG_TIDY_BIN)
    # attempt to find the binary if user did not specify
    find_program(CLANG_TIDY_BIN
            NAMES clang-tidy clang-tidy-10
            HINTS ${MINIOB_CLANG_SEARCH_PATH})
endif()
if ("${CLANG_TIDY_BIN}" STREQUAL "CLANG_TIDY_BIN-NOTFOUND")
    message(WARNING "MiniOB couldn't find clang-tidy.")
else()
    # Output compile_commands.json
    set(CMAKE_EXPORT_COMPILE_COMMANDS 1)
    message(STATUS "MiniOB found clang-tidy at ${CLANG_TIDY_BIN}")
endif()

# clang-apply-replacements
if (NOT DEFINED CLANG_APPLY_REPLACEMENTS_BIN)
    # attempt to find the binary if user did not specify
    find_program(CLANG_APPLY_REPLACEMENTS_BIN
        NAMES clang-apply-replacements clang-apply-replacements-10
        HINTS ${MINIOB_CLANG_SEARCH_PATH})
endif()
if("${CLANG_APPLY_REPLACEMENTS_BIN}" STREQUAL "CLANG_APPLY_REPLACEMENTS_BIN-NOTFOUND")
        message(WARNING "MiniOB couldn't find clang-apply-replacements.")
else()
    # Output compile_commands.json
    set(CMAKE_EXPORT_COMPILE_COMMANDS 1)
    message(STATUS "MiniOB found clang-apply-replacements at ${CLANG_APPLY_REPLACEMENTS_BIN}")
endif()

# cpplint
find_program(CPPLINT_BIN
        NAMES cpplint cpplint.py
        HINTS "${MINIOB_BUILD_SUPPORT_DIR}")
if ("${CPPLINT_BIN}" STREQUAL "CPPLINT_BIN-NOTFOUND")
    message(WARNING "MiniOB couldn't find cpplint.")
else()
    message(STATUS "MiniOB found cpplint at ${CPPLINT_BIN}")
endif()

# #####################################################################################################################
# Other CMake modules
# MUST BE ADDED AFTER CONFIGURING COMPILER PARAMETERS
# #####################################################################################################################
set(CMAKE_MODULE_PATH "${MINIOB_BUILD_SUPPORT_DIR}/cmake;${CMAKE_MODULE_PATH}")
find_package(LibElf)
find_package(LibDwarf)

######################################################################################################################
# MAKE TARGETS
######################################################################################################################

##########################################
# "make format"
# "make check-format"
##########################################

string(CONCAT MINIOB_FORMAT_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/src,"
        "${CMAKE_CURRENT_SOURCE_DIR}/test,"
        "${CMAKE_CURRENT_SOURCE_DIR}/unittest,"
        )

# runs clang format and updates files in place.
add_custom_target(format ${MINIOB_BUILD_SUPPORT_DIR}/run_clang_format.py
        ${CLANG_FORMAT_BIN}
        ${MINIOB_BUILD_SUPPORT_DIR}/clang_format_exclusions.txt
        --source_dirs
        ${MINIOB_FORMAT_DIRS}
        --fix
        --quiet
        )

# runs clang format and exits with a non-zero exit code if any files need to be reformatted
add_custom_target(check-format ${MINIOB_BUILD_SUPPORT_DIR}/run_clang_format.py
        ${CLANG_FORMAT_BIN}
        ${MINIOB_BUILD_SUPPORT_DIR}/clang_format_exclusions.txt
        --source_dirs
        ${MINIOB_FORMAT_DIRS}
        --quiet
        )


##########################################
# "make check-lint"
##########################################

file(GLOB_RECURSE MINIOB_LINT_FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/test/*.h"
        "${CMAKE_CURRENT_SOURCE_DIR}/test/*.cpp"
        )

# Balancing act: cpplint.py takes a non-trivial time to launch,
# so process 12 files per invocation, while still ensuring parallelism
add_custom_target(check-lint echo '${MINIOB_LINT_FILES}' | xargs -n12 -P8
        ${CPPLINT_BIN}
        --verbose=2 --quiet
        --linelength=120
        --filter=-legal/copyright,-build/header_guard,-runtime/references # https://github.com/cpplint/cpplint/issues/148
        )

# ##########################################################
# "make check-clang-tidy" target
# ##########################################################
# runs clang-tidy and exits with a non-zero exit code if any errors are found.
# note that clang-tidy automatically looks for a .clang-tidy file in parent directories
add_custom_target(check-clang-tidy
        ${MINIOB_BUILD_SUPPORT_DIR}/run_clang_tidy.py                     # run LLVM's clang-tidy script
        -clang-tidy-binary ${CLANG_TIDY_BIN}                              # using our clang-tidy binary
        -p ${CMAKE_BINARY_DIR}                                            # using cmake's generated compile commands
        # -clang-apply-replacements-binary ${CLANG_APPLY_REPLACEMENTS_BIN}  # using our clang-apply-replacements binary
        # -export-fixes clang-tidy.fixes                                    # `pip3 install pyyaml`
        ${CHECK_CLANG_TIDY_REGEX}
)
add_custom_target(fix-clang-tidy
        ${MINIOB_BUILD_SUPPORT_DIR}/run_clang_tidy.py                     # run LLVM's clang-tidy script
        -clang-tidy-binary ${CLANG_TIDY_BIN}                              # using our clang-tidy binary
        -p ${CMAKE_BINARY_DIR}                                            # using cmake's generated compile commands
        -clang-apply-replacements-binary ${CLANG_APPLY_REPLACEMENTS_BIN}  # using our clang-apply-replacements binary
        -fix                                                              # apply suggested changes generated by clang-tidy
        ${CHECK_CLANG_TIDY_REGEX}
)
add_custom_target(check-clang-tidy-diff
        ${MINIOB_BUILD_SUPPORT_DIR}/run_clang_tidy.py                     # run LLVM's clang-tidy script
        -clang-tidy-binary ${CLANG_TIDY_BIN}                              # using our clang-tidy binary
        -p ${CMAKE_BINARY_DIR}                                            # using cmake's generated compile commands
        -only-diff                                                        # only check diff files to master
)
add_custom_target(fix-clang-tidy-diff
        ${MINIOB_BUILD_SUPPORT_DIR}/run_clang_tidy.py                     # run LLVM's clang-tidy script
        -clang-tidy-binary ${CLANG_TIDY_BIN}                              # using our clang-tidy binary
        -p ${CMAKE_BINARY_DIR}                                            # using cmake's generated compile commands
        -clang-apply-replacements-binary ${CLANG_APPLY_REPLACEMENTS_BIN}  # using our clang-apply-replacements binary
        -fix                                                              # apply suggested changes generated by clang-tidy
        -only-diff                                                        # only check diff files to master
)