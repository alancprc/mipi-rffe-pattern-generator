DATE=$(shell date +%Y%m%d)
TARGET=mipiPatternGenerator_${DATE}
TARBALL=${TARGET}.tar.gz
PM=MipiPatternGenerator.pm
RELEASE=/net/shfs1/vol/training/training/PAx/Tools/mipiPatternGenerator

all : ${TARGET} ${TARBALL}

${PM} :
	ln -f ../lib/MipiPatternGenerator.pm

${TARGET} : ${PM}
	pp -f Crypto -F Crypto -M Filter::Crypto::Decrypt \
		-o ${TARGET} -x --xargs sample.cfg run.pl

${TARBALL} : ${TARGET} sample.csv sample.cfg sample.uno regtable_dut1.csv regtable_dut2.csv
	tar czf $@ $^
	tar tzf $@

release :
	rm -f ${RELEASE}/mipiPatternGenerator_*
	cp -at ${RELEASE} ${TARBALL}


clean :
	rm -f mipiPatternGenerator_*

