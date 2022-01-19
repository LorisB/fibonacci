# Copyright (c) 2022 Yegor Bugayenko
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
.PHONY: clean

INPUT = 32
WANTED = 8

CC=clang++
CCFLAGS=-mllvm --x86-asm-syntax=intel -O3 $$(if [ ! -f /.dockerenv ]; then echo "-fsanitize=leak"; fi)
RUSTC=rustc
RUSTFLAGS=-C opt-level=3
HC=ghc
HCFLAGS=-Wall -Werror
HCLIBDIR=haskell/Mainlib
HCLIBS=$(HCLIBDIR)/report.hs
HASKELLPREFIX=haskell_

DIRS=asm bin reports
CPPS = $(wildcard cpp/*.cpp)
RUSTS = $(wildcard rust/*.rs)
LISPS = $(wildcard lisp/*.lisp)
HASKELLS = $(wildcard haskell/*.hs)
ASMS = $(subst haskell/,asm/$(HASKELLPREFIX),$(subst lisp/,asm/,$(subst rust/,asm/,$(subst cpp/,asm/,${CPPS:.cpp=.asm} ${RUSTS:.rs=.asm} ${LISPS:.lisp=.asm} ${HASKELLS:.hs=.asm}))))
BINS = $(subst asm/,bin/,${ASMS:.asm=.bin})
REPORTS = $(subst bin/,reports/,${BINS:.bin=.txt})

summary.txt: env $(DIRS) $(ASMS) $(BINS) $(REPORTS) $(CYCLES) Makefile
	[ $$({ for r in $(REPORTS:.txt=.stdout); do cat $${r}; done ; } | uniq | wc -l) == 1 ]
	{
		date
		$(CC) --version | head -1
		echo "INPUT=$(INPUT)"
		echo
		for r in $(REPORTS); do cat $${r}; done
	} > summary.txt
	cat "$@"

summary.csv: $(DIRS) $(REPORTS)
	{ for r in $(REPORTS:.txt=.csv); do cat $${r}; done } > summary.csv
	cat summary.csv

env:
	$(CC) --version
	$(RUSTC) --version
	$(MAKE) -version

sa: Makefile
	diff -u <(cat $${targets}) <(clang-format --style=file $(CPPS))
	cppcheck --inline-suppr --enable=all --std=c++11 --error-exitcode=1 $(CPPS)
	cpplint --extensions=cpp --filter=-whitespace/indent $(CPPS)
	clang-tidy -header-filter=none \
		'-warnings-as-errors=*' \
		'-checks=*,-readability-magic-numbers,-altera-id-dependent-backward-branch,-cert-err34-c,-cppcoreguidelines-avoid-non-const-global-variables,-readability-function-cognitive-complexity,-misc-no-recursion,-llvm-header-guard,-cppcoreguidelines-init-variables,-altera-unroll-loops,-clang-analyzer-valist.Uninitialized,-llvmlibc-callee-namespace,-cppcoreguidelines-no-malloc,-hicpp-no-malloc,-llvmlibc-implementation-in-namespace,-bugprone-easily-swappable-parameters,-llvmlibc-restrict-system-libc-headers,-llvm-include-order,-modernize-use-trailing-return-type,-cppcoreguidelines-special-member-functions,-hicpp-special-member-functions,-cppcoreguidelines-owning-memory,-cppcoreguidelines-pro-type-vararg,-hicpp-vararg' \
		$(CPPS)

asm/%.asm: cpp/%.cpp
	$(CC) $(CCFLAGS) -S -o "$@" "$<"

asm/%.asm: rust/%.rs
	$(RUSTC) $(RUSTFLAGS) --emit=asm -o "$@" "$<"

asm/%.asm: lisp/%.lisp
	echo " no asm here" > "$@"

asm/$(HASKELLPREFIX)%.asm: haskell/%.hs $(HCLIBS)
	source=$$( echo "$<" | sed 's/\.hs$$//' )
	$(HC) $(HCFLAGS) -S $(HCLIBS) "$<"
	mv $${source}.s "$@"
	cat $(HCLIBDIR)/*.s >> "$@"
	rm $(HCLIBDIR)/*.s

bin/%.bin: cpp/%.cpp
	$(CC) $(CCFLAGS) -o "$@" "$<"

bin/%.bin: rust/%.rs
	$(RUSTC) $(RUSTFLAGS) -o "$@" "$<"

bin/%.bin: lisp/%.lisp
	sbcl --load "$<"

bin/$(HASKELLPREFIX)%.bin: haskell/%.hs $(HCLIBS)
	source=$$( echo "$<" | sed 's/\.hs$$//' )
	$(HC) $(HCFLAGS) $(HCLIBS) "$<"
	mv $${source} "$@"
	rm $${source}.o
	rm $${source}.hi
	rm $(HCLIBDIR)/*.o
	rm $(HCLIBDIR)/*.hi

reports/%.txt: bin/%.bin asm/%.asm Makefile $(DIRS)
	"$<" 7 1
	cycles=1
	while true; do
		time=$$({ time -p "$<" $(INPUT) $${cycles} | head -1 > "${@:.txt=.stdout}" ; } 2>&1 | head -1 | cut -f2 -d' ')
		echo $${time} > "${@:.txt=.time}"
		echo "cycles=$${cycles}; time=$${time} -> too fast, need more cycles..."
		if [ "$(FAST)" != "" ]; then break; fi
		seconds=$$(echo $${time} | cut -f1 -d.)
		if [ "$${seconds}" -gt "10" ]; then break; fi
		if [ "$${seconds}" -gt "0" -a "$${cycles}" -ge "$(WANTED)" ]; then break; fi
		cycles=$$(expr $${cycles} \* 2)
		if [ "$${cycles}" -lt "$(WANTED)" -a "$${seconds}" -lt "1" ]; then cycles=$(WANTED); fi
	done
	instructions=$$(grep -e $$'^\(\t\| \)\+[a-z]\+' "$(subst bin/,asm/,${<:.bin=.asm})" | wc -l | xargs)
	per=$$(echo "scale = 16 ; $${time} / $${cycles}" | bc)
	{
	  	echo "$<:"
	  	echo "Instructions: $${instructions}"
		echo "Cycles: $${cycles}"
		echo "Time: $${time}"
		echo "Per cycle: $${per}"
		echo ""
	} > "$@"
	echo "${subst bin/,,$<},$${instructions},$${cycles},$${time},$${per}" > "${@:.txt=.csv}"

clean:
	rm -rf $(DIRS)
	rm -f summary.txt summary.csv

$(DIRS):
	mkdir "$@"
