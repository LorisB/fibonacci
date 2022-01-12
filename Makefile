# Copyright (c) 2016-2022 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SHELL=/bin/bash
.ONESHELL:
.SHELLFLAGS = -e -o pipefail -c

DIRS=asm bin reports
C_SOURCES = $(wildcard *.c)
CPP_SOURCES = $(wildcard *.cpp)
ASMS = $(addprefix asm/,${C_SOURCES:.c=.c.asm} ${CPP_SOURCES:.cpp=.cpp.asm})
BINS = $(subst asm/,bin/,${ASMS:.asm=.bin})
REPORTS = $(subst bin/,reports/,${BINS:.bin=.txt})

summary.txt: env $(DIRS) $(ASMS) $(BINS) $(REPORTS) sa Makefile
	[ $$({ for r in $(REPORTS:.txt=.stdout); do cat $${r}; done ; } | uniq | wc -l) == 1 ]
	for r in $(REPORTS); do cat $${r}; done > summary.txt
	cat "$@"

env:
	clang++ --version | head -1
	 $(MAKE) -version | cat | head -1

sa:
	clang-tidy -format-style=google '-checks=*,-llvm-include-order,-cppcoreguidelines-special-member-functions,-hicpp-special-member-functions,-cppcoreguidelines-owning-memory,-cppcoreguidelines-pro-type-vararg,-hicpp-vararg' '-warnings-as-errors=*' $(C_SOURCES) $(CPP_SOURCES)

asm/%.c.asm: %.c metrics.h
	clang -S -mllvm --x86-asm-syntax=intel -o "$@" "$<"

asm/%.cpp.asm: %.cpp metrics.h
	clang++ -S -mllvm --x86-asm-syntax=intel -o "$@" "$<"

bin/%.bin: asm/%.asm
	clang++ -o "$@" "$<"

reports/%.txt: bin/%.bin
	{ time -p "$<" > "${@:.txt=.stdout}" ; } 2>&1 | head -1 | cut -f2 -d' ' > "${@:.txt=.time}"
	echo "$<:" > "$@"
	echo "Instructions: $$(grep -e '^\t[a-z]\+\t' "$(subst bin/,asm/,${<:.bin=.asm})" | wc -l | xargs)" >> "$@"
	echo "Time: $$(cat "${@:.txt=.time}")" >> "$@"
	echo "" >> "$@"

.PHONY: clean
clean:
	rm -rf $(DIRS)

$(DIRS):
	mkdir "$@"
