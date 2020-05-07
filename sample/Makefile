DATE=$(shell date +%Y%m%d)
TARGET=mipiPatternGenerator_${DATE}
TARBALL=${TARGET}.tar.gz
PM=MipiPatternGenerator.pm

all : ${TARGET} ${TARBALL}

${PM} :
	ln -f ../lib/MipiPatternGenerator.pm

${TARGET} : ${PM}
	pp -f Crypto -F Crypto -M Filter::Crypto::Decrypt \
		-o ${TARGET} -x --xargs sample.txt run.pl

${TARBALL} : ${TARGET} sample.txt sample.uno regtable_dut1.csv regtable_dut2.csv
	tar czf $@ $^
	tar tzf $@

clean :
	rm -f mipiPatternGenerator_*

