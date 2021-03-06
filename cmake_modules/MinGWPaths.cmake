# Copyright 2010 Matthew Arsenault, Travis Desell, Dave Przybylo,
# Nathan Cole, Boleslaw Szymanski, Heidi Newberg, Carlos Varela, Malik
# Magdon-Ismail and Rensselaer Polytechnic Institute.

# This file is part of Milkway@Home.

# Milkyway@Home is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Milkyway@Home is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with Milkyway@Home.  If not, see <http://www.gnu.org/licenses/>.
#

if(MINGW)
  if(NOT MINGW_ROOT)
    set(MINGW_ROOT "C:/MinGW/")
  endif()

  if(MSYS)
    if(NOT MSYS_ROOT)
      set(MSYS_ROOT "C:/MinGW/msys/1.0")
    endif()
    set(CMAKE_LIBRARY_PATH "${MSYS_ROOT}/local/lib"
                           "${MSYS_ROOT}/lib"
                           "${MINGW_ROOT}/lib")
    set(CMAKE_INCLUDE_PATH "${MSYS_ROOT}/local/include"
                           "${MSYS_ROOT}/include"
                           "${MINGW_ROOT}/include")
  endif()
endif()

