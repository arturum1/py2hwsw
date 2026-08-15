# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

PNGS=$(patsubst %.drom,%.png,$(wildcard *.drom))

all: clean $(PNGS)

%.png: %.svg
	rsvg-convert -b '#ffffff' $< -o $@
	rm -rf *.svg

%.svg: %.drom
	wavedrompy -i $< -s $@

clean:
	rm -rf *.png

.PHONY: all clean
	
