// Date:     April 14, 2021
// Class:    COP 4600
//           University of Florida
//           Team 145
// Team Members Greg Bolling & Jovencey StFleur
// Semester: Spring 2021
// File      nutshell.c
//
// Implements:  Nutshell Project
//              Holds the main loop that calls the yacc/bison side that calls the lex/flex side
//              and runs each command under nutshparser.y.  It needs access to environment variables
//              and puts a starter in them.  Ubuntu does not have commands under /usr/bin so the starting
//              path includes /bin
//
// This began as a demo micro-shell and has been greatly expanded.  Many thanks to the UF TA staff for the starting point
// that has grown to become a much larger shell.  The commands implemented are from the assignment and grew slowly
// until it reached completion.  The starting point of parsing with flex/bison was much appreciated.
//
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <pwd.h>
#include <errno.h>
#include <fcntl.h>  
#include <fnmatch.h>
#include <string.h>
#include "global.h"

char *getcwd(char *buf, size_t size);
int yyparse();
void EraseAllPendingCommands( void );

int findPromptEnvVariable(char *varname ) {
    bool foundit = false;
	int i;
	
	for (i = 0; (i < varIndex) && (!foundit); i++) {  // search for the alias
	    if(strcmp(varTable.var[i], varname) == 0) {
		    foundit = true;
		}
	}
	
	if (foundit) {
	   return i-1;
	} else {
	   return -1;
	}
}
void ChildDepartingFunction(int signalinput) {       // background commands end up here
 pid_t pid_t;
 int retval;
 pid_t  = waitpid(-1, &retval, 0);                   // see https://www.ibm.com/docs/en/zos/2.1.0?topic=functions-waitpid-wait-specific-child-process-end                                  
}

int main()
{
    aliasIndex = 0;
    varIndex = 0;
	backgroundSet = false;
    struct passwd* pwd;
	                                            // see manual at https://man7.org/linux/man-pages/man2/signal.2.html
                                                // see examples at https://docs.oracle.com/cd/E19455-01/806-4750/signals-7/index.html
    signal(SIGCHLD, ChildDepartingFunction);    // /whenever a child dies, it sends that signal to this function

    EraseAllPendingCommands( );
    getcwd(cwd, sizeof(cwd));

    strcpy(varTable.var[varIndex], "PWD");
    strcpy(varTable.word[varIndex], cwd);
    varIndex++;
    strcpy(varTable.var[varIndex], "HOME");
	pwd = getpwuid(getuid());
    strcpy(varTable.word[varIndex], pwd->pw_dir);
    varIndex++;
    strcpy(varTable.var[varIndex], "PROMPT");
    strcpy(varTable.word[varIndex], "Team145Shell");
    varIndex++;
    strcpy(varTable.var[varIndex], "PATH");
    strcpy(varTable.word[varIndex], ".:/bin:/usr/bin");
    varIndex++;

    system("clear");
	int getPrompt;
    while(1)
    {
		getPrompt = findPromptEnvVariable("PROMPT");
		if (getPrompt == -1) {
           printf(">> ");
		} else {
           printf("[%s]>> ", varTable.word[getPrompt]);
		}
        yyparse();
    }

   return 0;
}