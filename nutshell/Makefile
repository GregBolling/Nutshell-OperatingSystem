CC=/usr/bin/cc

all:  clean bison-config flex-config nutshell

bison-config:
	bison -d nutshparser.y

flex-config:
	flex nutshscanner.l

delnutshell: 
	touch nutshell 
	rm nutshell
	
nutshell: 
	$(CC) nutshell.c nutshparser.tab.c lex.yy.c -o nutshell

clean:
	touch nutshparser.tab.c
	touch nutshparser.tab.h
	touch lex.yy.c
	touch nutshell
	rm nutshparser.tab.c nutshparser.tab.h lex.yy.c nutshell
