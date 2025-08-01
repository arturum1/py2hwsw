# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# Makefile for creating documents in the build directory

SHELL = bash

# include core basic info
include ../config_build.mk

#include local doc makefile segment
ifneq ($(wildcard doc_build.mk),)
include doc_build.mk
endif

#default DOC
DOC?=ug

TSRC = $(patsubst tsrc/%, ./%, $(wildcard tsrc/*))
%.tex: tsrc/%.tex
	cp $< $@
%.cls: tsrc/%.cls
	cp $< $@
%.py: tsrc/%.py
	cp $< $@
%.h: tsrc/%.h
	cp $< $@
%.c: tsrc/%.c
	cp $< $@

TSRC+=name.tex

TSRC+=signature.tex
signature.tex: $(DOC)_signature.tex
	mv $< $@

ug_signature.tex pb_signature.tex:
	@echo `cat name.tex`-USG-`cat $(NAME)_version.tex`-`cat shortHash.tex` > $@

rn_signature.tex:
	@echo `cat name.tex`-REL-`cat $(NAME)_version.tex`-`cat shortHash.tex` > $@


#make figures
figs:
	make -C ./figures figs

pb_figs:
	make -C ./figures pb_figs

#doxygen documentation
ifeq ($(DOXYGEN),1)
TSRC+=doxygen.tex
doxygen.tex: doxygen
	cp doxygen/latex/*.tex .
	cp doxygen/latex/*.sty .
	cp doxygen/*.sty . # copy custom .sty files after generated doxygen .sty
	cp doxygen/doxygen.tex $@

doxygen:
	make -C ./doxygen all
endif

#build document
build: debug $(DOC).pdf

#build presentation document type
presentation.pdf: figs presentation.tex
	pdflatex -jobname pres presentation.tex
	pdflatex -jobname pres presentation.tex

#build product brief document type
pb.pdf: debug results pb_figs pbtop.tex
	pdflatex -jobname pb pbtop.tex
	pdflatex -jobname pb pbtop.tex

#pb top file containing the definition of sections to include
pbtop.tex:
	make doctop DOC=pb

#build user guide document type
ug.pdf: debug results figs ugtop.tex
	pdflatex -jobname ug ugtop.tex
	if [ -f *.bib ]; then bibtex ug; fi
	pdflatex -jobname ug ugtop.tex
	pdflatex -jobname ug ugtop.tex


#ug top file containing the definition of sections to include
ugtop.tex:
	if ls *_iob_params_tab.tex > /dev/null 2>&1; then echo "\def\IOBPARAMS{Y}" >> $@; fi
	if ls *_confs_tab.tex > /dev/null 2>&1; then echo "\def\CONFS{Y}" >> $@; fi
	if [ -f td.tex ]; then echo "\def\TD{Y}" >> $@; fi
	if ls *_csrs_tab.tex > /dev/null 2>&1; then echo "\def\CSRS{Y}" >> $@; fi
	if [ -f mems_tab.tex ]; then echo "\def\MEMS{Y}" >> $@; fi
	if [ $(ASICSYNTH) == 1 ]; then echo "\def\ASICSYNTH{Y}" >> $@; fi
	if [ $(FPGACOMP) == 1 ]; then echo "\def\FPGACOMP{Y}" >> $@; fi
	if [ $(DOXYGEN) == 1 ]; then echo "\def\DOXYGEN{Y}" >> $@; fi
	make doctop DOC=ug

#include implementation results if available

ifneq ($(wildcard quartus.tex),)
INTEL_FPGA:=1
endif

ifneq ($(wildcard vivado.tex),)
AMD_FPGA:=1
endif

RESULTS = $(INTEL_FPGA)$(AMD_FPGA)$(UMC130_ASIC)

rntop.tex:
	make doctop DOC=rn

rn.pdf: rntop.tex
	pdflatex -jobname rn rntop.tex
	pdflatex -jobname rn rntop.tex


doctop:
	echo "\def\NAME{$(NAME)}" >> $(DOC)top.tex
ifeq ($(DOC),rn)
	echo "\def\RN{Y}" >> $(DOC)top.tex
endif
	if [ $(SECTIONCLEARPAGE) ]; then echo "\def\SECTIONCLEARPAGE{Y}" >> $(DOC)top.tex; fi
	if [ $(RESULTS) ]; then echo "\def\RESULTS{Y}" >> $(DOC)top.tex; fi
	if [ $(INTEL_FPGA)$(AMD_FPGA) ]; then echo "\def\FPGA{Y}" >> $(DOC)top.tex; fi
	if [ $(AMD_FPGA) ]; then echo "\def\AMD{Y}" >> $(DOC)top.tex; fi
	if [ $(INTEL_FPGA) ]; then echo "\def\INTEL{Y}" >> $(DOC)top.tex; fi
	if [ $(ASIC_NODE) ]; then echo "\def\ASIC{Y}" >> $(DOC)top.tex; fi
	if [ -f custom.tex ]; then echo "\def\CUSTOM{Y}" >> $(DOC)top.tex; fi
	echo "\input{$(DOC).tex}" >> $(DOC)top.tex


#view document
view: $(DOC).pdf
	evince $< &

clean:
	@find . -maxdepth 1 -type f -not \( -name \*.pdf -o -name Makefile -o -name \*.mk -o -name $(NAME)\* \) -delete
	@rm -rf $(PYTHON_DIR)/__pycache__ ../*.tex

veryclean: clean
	make -C figures clean 

test: clean debug ug.pdf clean debug pb.pdf clean debug
	if [ -f tsrc/presentation.tex ]; then make presentation.pdf; fi

debug: $(TSRC)
	@echo TSRC=$(TSRC)
	@echo RESULTS=$(RESULTS)
	@echo FPGA=$(FPGA)
	@echo INTEL_FPGA=$(INTEL_FPGA)
	@echo AMD_FPGA=$(AMD_FPGA)
	@echo ASIC_NODE=$(ASIC_NODE)

.PHONY: view doctop figs results build clean test debug doxygen

