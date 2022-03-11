// Date:     April 14, 2021
// Class:    COP 4600
//           University of Florida
//           Team 145
// Team Members Greg Bolling & Jovencey StFleur
// Semester: Spring 2021
// File      global.h
//
// Implements:  Nutshell Project
//              Holds the global definitions for the operating systems nutshell project.
//

#include "stdbool.h"
#include <limits.h>

// set these to false to turn off debug print statements prior to final build and release
/*
#define DEBUGMODEUNALIAS     true
#define DEBUGMODEUNVARIABLE  true
#define DEBUGMODESETVARIABLE true
#define DEBUGMODEGETVARIABLE true
#define DEBUGFORKINGCOMMANDS true
#define DEBUGPARSER          true
#define DEBUGEXECCMD         true
#define DEBUGEXECCMDEXTRA    true
#define DEBUGEXECCMDVERYLONG true
*/

#define DEBUGMODEUNALIAS     false
#define DEBUGMODEUNVARIABLE  false
#define DEBUGMODESETVARIABLE false
#define DEBUGMODEGETVARIABLE false
#define DEBUGFORKINGCOMMANDS false
#define DEBUGPARSER          false
#define DEBUGEXECCMD         false
#define DEBUGEXECCMDEXTRA    false
#define DEBUGEXECCMDVERYLONG false


#define MAXENVVARS       256
#define MAXENVVARLENGTH  256
#define MAXALIASES       256
#define MAXALIASLENGTH   256
#define MAXPARAMETERS    256
#define MAXCMDPARLENGTH  256
#define MAXCOMMANDS      256
#define MAXFILENAMELEN   256

struct evTable {
   char var[MAXENVVARS][MAXENVVARLENGTH];
   char word[MAXENVVARS][MAXENVVARLENGTH];
};

struct aTable {
	char name[MAXALIASES][MAXALIASLENGTH];
	char word[MAXALIASES][MAXALIASLENGTH];
};

char cwd[PATH_MAX];

struct evTable varTable;

struct aTable aliasTable;

char buildUpString[MAXALIASLENGTH];
char buildUpString2[MAXALIASLENGTH];
char splitDirectory[MAXALIASLENGTH];
char splitFilename[MAXALIASLENGTH];
char removeQuotes[MAXALIASLENGTH];

int aliasIndex, varIndex;

char* subAliases(char* name);

struct command_format {
	int pipefd[2];                                 // this command pipeline
	char command[MAXCMDPARLENGTH];                 // the first command to be run, this can be from the path or from a listed item in here
	char params[MAXPARAMETERS][MAXCMDPARLENGTH];   // the parameters that come along with the command, up to 100 of them
	int parameter_count;                           // the total number of parameters in params[0..parameter_count-1] above
	
};
int builtin_fd_in;
int builtin_fd_out;
int builtin_fd_err; //open("file.txt", O_WRONLY|O_CREAT, 0666);
struct command_format commandParsing[MAXCOMMANDS];
int commandParsingIndex;
bool backgroundSet;
bool errorDoNotExecute;                            // when false, no problems, but gets set to true when something happened
                                                   // that makes this command impossible to execute like not being able to
												   // open up a file or not being able to run a command.