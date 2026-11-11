# Conda's CUDA-enabled LibTorch can export CUDA::cudart_static through an
# imported target's link interface. CUDA DSOs such as libtorch_cuda.so then
# reference hidden symbols that only exist in the shared runtime, which makes
# the final executable link fail with "hidden symbol ... referenced by DSO".
if(NOT CP2K_USE_CUDA)
  return()
endif()

function(cp2k_replace_static_cudart target)
  if(NOT TARGET "${target}")
    return()
  endif()
  # These targets describe the static runtime itself. Do not rewrite them;
  # only replace references to them from other imported targets.
  if(target STREQUAL "CUDA::cudart_static"
      OR target STREQUAL "CUDA::cudart_static_deps")
    return()
  endif()

  foreach(property INTERFACE_LINK_LIBRARIES INTERFACE_LINK_OPTIONS)
    get_target_property(link_items "${target}" "${property}")
    if(link_items AND link_items MATCHES
        "(^|[^A-Za-z0-9_])cudart_static([^A-Za-z0-9_]|$)")
      string(REGEX REPLACE
        "CUDA::cudart_static(_deps)?([^A-Za-z0-9_]|$)"
        "CUDA::cudart\\2" link_items "${link_items}")
      string(REPLACE "-lcudart_static" "-lcudart" link_items "${link_items}")
      string(REPLACE "libcudart_static.a" "libcudart.so" link_items "${link_items}")
      set_property(TARGET "${target}" PROPERTY "${property}" "${link_items}")
      message(STATUS
        "CP2K: using shared CUDA runtime instead of static in ${target} (${property})")
    endif()
  endforeach()
endfunction()

get_property(imported_targets DIRECTORY PROPERTY IMPORTED_TARGETS)
foreach(target IN LISTS imported_targets)
  cp2k_replace_static_cudart("${target}")
endforeach()

# Fail during configure if an imported target still propagates a static CUDA
# runtime. This catches LibTorch package layouts that our replacement misses.
foreach(target IN LISTS imported_targets)
  if(target STREQUAL "CUDA::cudart_static"
      OR target STREQUAL "CUDA::cudart_static_deps")
    continue()
  endif()
  foreach(property INTERFACE_LINK_LIBRARIES INTERFACE_LINK_OPTIONS)
    get_target_property(link_items "${target}" "${property}")
    if(link_items AND link_items MATCHES
        "(^|[^A-Za-z0-9_])cudart_static([^A-Za-z0-9_]|$)")
      message(FATAL_ERROR
        "${target} still exports cudart_static in ${property}: ${link_items}")
    endif()
  endforeach()
endforeach()
