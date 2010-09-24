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

macro(set_mingw_paths)
  if(MINGW)
    if(NOT TAKEOFFGW_ROOT)
      set(TAKEOFFGW_ROOT "C:/takeoffgw/")
    endif(NOT TAKEOFFGW_ROOT)

    set(CMAKE_FIND_ROOT_PATH "${TAKEOFFGW_ROOT}/i686-pc-mingw32/sys-root/mingw")
  endif(MINGW)
endmacro()
