%{
// Date:     April 14, 2021
// Class:    COP 4600
//           University of Florida
//           Team 145
// Team Members Greg Bolling & Jovencey StFleur
// Semester: Spring 2021
// File      nutshparser.y
//
// Implements:  Nutshell Project
//              Holds the yacc / bison side and executes the commands.  When it sees a command
//              runs the command.  
//
// This began as a demo micro-shell and has been greatly expanded.  Many thanks to the UF TA staff for the starting point
// that has grown to become a much larger shell.  The commands implemented are from the assignment and grew slowly
// until it reached completion.  The starting point of parsing with flex/bison was much appreciated.
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


int yylex(void);                             // list all the functions in case they are called before being defined
int yyerror(char *s);
int runCD(char* arg);
int runSetAlias(char *name, char *word);
int runSetVariable(char *varname, char *word);
int runUnsetVariable(char *varname);
int runPrintAlias(void);
int runPrintEnv(void);
int runUnsetAlias(char *name);
void RedirectStdOutAppendCommandParsing( char * redirectLocation );
void RedirectStdOutCommandParsing( char * redirectLocation );
void RedirectStdErrCommandParsing( char * redirectLocation );
void RedirectStdInCommandParsing( char * redirectLocation );
void EraseAllPendingCommands( void );
void runStringFoundRedirect( char* arg, int redirect_out_capture);
int runStringFoundCommand( char* arg);
int runStringFoundParameters( char* arg);
int runStringFoundEnd( char* arg,  char* arg2  );
int redirect_out_capture;
void runBackgroundOp( void );
bool runGetVariable(char *varname, char *destinationword);
bool LookForFileMatchHere( char * directory, char * filenamein, char * matchname);
bool LookForFileMatchInPath( char * filenamein, char * matchname);
bool CheckAndCorrectCommandsPending( void );
void ExecuteAllCommandsPending( void );
bool ExecuteOneCommand( int cmd_num );
void runCDHOME(void);
bool checkForWildcard( char * source);
bool TestWildcardMatch( char * wildcardin, char * exactnamein);
void wildcardExpansion( char * source);
char* clearQuotes(char* parameter);

%}

%union {char *string;}

%start cmd_line
%token <string> BYE CD PIPE STRING ALIAS SETENV  SINGLEQUOTE 
        UNSETENV PRINTENV UNALIAS END REDIRECTSTDOUT  BACKGROUNDOP ESCAPEKEY
	   REDIRECTERROUT REDIRECTSTDOUTAPPEND REDIRECTSTDIN REDIRECTERROUTSTDOUT // BACKGROUND

%%
cmd_line    :
	END 		                          {return 1; }                           // Ignores user entering nothing, was creating "syntax error" from yacc
	| BYE END 		                      {exit(1); return 1; }                  // "bye <enter>"
	| CD STRING END        		          {runCD($2); return 1; }                // "cd location <enter>"
	| CD  END        		              {runCDHOME(); return 1; }              // "cd <enter>" goes to home directory of user
	| PRINTENV redirect END		          {runPrintEnv(); return 1; }
	| UNSETENV STRING END	              {runUnsetVariable($2); return 1; }     // "unsetenv variablename <enter>"
	| SETENV STRING STRING END            {runSetVariable($2, $3); return 1; }   // "setenv envvar name <enter>"
	| ALIAS redirect END	              {runPrintAlias(); return 1; }          // "alias (> or >>) location <enter>"
	| ALIAS STRING STRING END		      {runSetAlias($2, $3); return 1; }
	| UNALIAS STRING END		          {runUnsetAlias($2); return 1; } 
	| oneormorecommands redirect background END { ExecuteAllCommandsPending(); if(DEBUGPARSER){printf("0 oneormorecommands redirect END\n");} 
	                                        // this will now launch the sequence of commands here
											// all commands have been gathered,
											// and pipes are inbetween them,
											// all the redirections have been entered too.
	                                        return 1;}   
	//| END                               {return 1;} //{return 1;}  
;

background :
     | BACKGROUNDOP                       { runBackgroundOp();
	                                        if(DEBUGPARSER){printf("2 BACKGROUNDOP\n");}}
       
redirect :
     | redirectop redirectdest            { if(DEBUGPARSER){printf("3 redirectop redirectdest\n");}}
     | redirect redirectop redirectdest   { if(DEBUGPARSER){printf("4 redirect redirectop redirectdest\n");}}
redirectdest :
      STRING                              { runStringFoundRedirect($1, redirect_out_capture);
	                                        if(DEBUGPARSER){printf("5 redirectdest STRING.\n"); }}  
     | REDIRECTERROUTSTDOUT               { if(DEBUGPARSER){printf("6 REDIRECTERROUTSTDOUT\n"); 
	                                        runStringFoundRedirect($1, REDIRECTERROUTSTDOUT);}}  
redirectop :
     REDIRECTSTDOUT                       { redirect_out_capture = REDIRECTSTDOUT;
	                                        if(DEBUGPARSER){printf("7 REDIRECTSTDOUT\n"); }}
     | REDIRECTERROUT                     { redirect_out_capture = REDIRECTERROUT;
	                                        if(DEBUGPARSER){printf("8 REDIRECTERROUT\n"); }}
     | REDIRECTSTDOUTAPPEND               { redirect_out_capture = REDIRECTSTDOUTAPPEND;
	                                        if(DEBUGPARSER){printf("9 REDIRECTSTDOUTAPPEND\n"); }}
     | REDIRECTSTDIN                      { redirect_out_capture = REDIRECTSTDIN;
	                                        if(DEBUGPARSER){printf("10 REDIRECTSTDIN\n"); }}
oneormorecommands : 
     commandin paramsin                           { if(DEBUGPARSER){printf("11 Single Command\n");}}
	 | oneormorecommands PIPE oneormorecommands   { if(DEBUGPARSER){printf("12 PIPE singlecommands.\n");}}
  
paramsin : 
    | paramsin STRING                     { runStringFoundParameters($2);
	                                        if(DEBUGPARSER){printf("13 paramsin STRING.\n");}} 
    | STRING                              { runStringFoundParameters($1);  
	                                        if(DEBUGPARSER){printf("14 paramsin STRING.\n");}} 
	   
commandin : 
      STRING                              { runStringFoundCommand($1);  if(DEBUGPARSER){printf("15 Command STRING.\n");}} 
;
%%

int yyerror(char *s) {                            // maybe use this to figure out single quotes ' incoming parsing...
  printf("%s\n",s);
  return 0;
  }

void runCDHOME( void ) {
	char homecopy[MAXFILENAMELEN] = "";           // copies the HOME variable
	bool result;                                  // output from any function call 
	result = runGetVariable("HOME", homecopy);
    if(chdir(homecopy) != 0) {
        printf("HOME Directory [%s] not found\n", homecopy);
    }
}

bool checkForWildcard( char * source) {                  // looks at the incoming string searching for '?' or '*'
    char *findChar;                                      // pointer that increments while looking for the character in source
	bool  retVal = false;                                // return value starts out false, true if one is found below
	findChar = source;                                   // start pointer at the front of the string
	while(*findChar != '\0') {                           // search every character and stop when it reaches the null termination
	    if ((*findChar == '*') || (*findChar == '*')) {  // if one is a * or ?, this has wildcards...
		   retVal = true;                                // return true if there was a wildcard character
        }		
		findChar++;                                      // increment the pointer 
	}
	return retVal;                                       // return the result
}  
bool ReturnAllMatches( char * directory, char * filenamein, char * matchname) {
     bool matchFound = false;
	 int numberFound;
	 char destination[MAXFILENAMELEN];                                            // final assembled result, copied back to source
	 struct dirent **listOfFiles;                                                 // so listOfFiles[0]->d_name has the first file name, etc...
	                                                                              // and the code only needs the first match so this is the one to use
									                                              // must deallocate the memory because scandir allocates memory.
	 numberFound = scandir(directory, &listOfFiles, NULL, alphasort);             // get the SORTED files in a list and the total count
     strcpy(destination, "");                                                     // start with no matches
     if (numberFound > 0) {                                                       // no files were found that match the file or error...
		for(int j = 0; j <numberFound; ++j) {                                     // look at all files in this directory
		   if (TestWildcardMatch( filenamein, listOfFiles[j]->d_name)) {          // test for a wildcard match to this file name
			   matchFound = true;                                                 // remember a match was found
               strcat(destination,listOfFiles[j]->d_name);                        // copy this match to the destination
               strcat(destination," ");                                           // separate by a space
		   }
		}	
        free(listOfFiles);                                                        // release memory to allocated by scandir() above
    }
	if (matchFound) {                                   // if we found a match
	    strcpy(matchname, destination);                 // use the new list
	} else {
	    strcpy(matchname, filenamein);                  // use the original incoming value
	}
	return matchFound;
}

void wildcardExpansion( char * source){                   // performs wildcard expansion and returns back to source
	char destination[MAXFILENAMELEN];                    // final assembled result, copied back to source
	if (checkForWildcard(source) == true) {              // see if anything needs to be done 
	    ReturnAllMatches("./", source, destination);     // go get results in destination
		strcpy(source, destination);                     // copy back to source and return
	}
}

int runCD(char* arg) {
    struct passwd* pwd;
	char finalPath[MAXFILENAMELEN];
	
	
	if (arg[0] != '/') {                                                     // arg is relative path such as "./test.dir" or "test.dir"                       
	    strcpy(finalPath, varTable.word[0]);                                 // start with PWD value 
		strcat(finalPath, "/");                                              // add a '/' character
		strcat(finalPath, arg);                                              // add what remains of the path
	    if(DEBUGEXECCMD) {printf(" found change directory to %s\n", finalPath);}
		if(chdir(finalPath) == 0) {                                          // change the directory
			getcwd(cwd, sizeof(cwd));                                        // get the PWD
			strcpy(varTable.word[0], cwd);                                   // make it the new PWD
			return 1;
		}
		else {
			getcwd(cwd, sizeof(cwd));                                        // the chdir failed
			strcpy(varTable.word[0], cwd);                                   // copy to current directory where ever it landed to PWD
			printf("Directory not found\n");                                 // notify user of failure
			return 1;
		}
	}
	else {                                                                   // arg is absolute path
	    if(DEBUGEXECCMD) {printf(" found change directory to %s\n", arg);}
		if(chdir(arg) == 0){                                                 // change the directory
			strcpy(varTable.word[0], arg);                                   // copy arg to PWD
			return 1;
		} 
		else {
			printf("Directory not found\n");                                 // chdir failed, notify user
            return 1;
		}
	}
}

bool TestWildcardMatch( char * wildcardin, char * exactnamein) {
  bool retVal = false;
  if (fnmatch( wildcardin, exactnamein, 0 ) == 0) {
     retVal = true;
  }
  return retVal;
}
 
bool LookForFileMatchHere( char * directory, char * filenamein, char * matchname) {
     // matchname must be able to handle MAXFILENAMELEN (256) characters by the below string format for dirent
     // takes in the directory name such as "." and searches it for occurrences of 
	 // filenamein.  if it is found, it returns true and stores the matched filename in matchname 
	 // When this is a wildcard match, the actual file is returned.  it gets turned into an exact match...
	 // the search can be done one directory at a time with this calling function.
	 // see manuals https://man7.org/linux/man-pages/man3/scandirat.3.html 
	 // see manuals https://www.man7.org/linux/man-pages/man3/readdir.3.html
     bool retVal = false;
	 int numberFound;
	 int locationfound = 0;
	 struct dirent **listOfFiles;                                                 // so listOfFiles[0]->d_name has the first file name, etc...
	                                                                              // and the code only needs the first match so this is the one to use
									                                              // must deallocate the memory because scandir allocates memory.
	 numberFound = scandir(directory, &listOfFiles, NULL, alphasort);             // get the files in a list and the total count
	 if (DEBUGEXECCMDVERYLONG) { printf(" LookForFileMatchHere found %d instances\n", numberFound); }
     if (numberFound < 0) {                                                       // no files were found that match the file or error...
        retVal = false;                                                           // set error condition and notify user of PATH problem
		printf("PATH variable has an error searching %s\n Reason: %s\n", directory, strerror(errno));
     } else {   
		for(int j = 0; j <numberFound; ++j) {  
		   if (DEBUGEXECCMDVERYLONG) { printf(" Checking %s to listOfFiles[%d]=%s\n", filenamein, j, listOfFiles[j]->d_name); }
		   if (TestWildcardMatch( filenamein, listOfFiles[j]->d_name)) {
			   locationfound = j;
     		   if (DEBUGEXECCMDVERYLONG) { printf(" Matched %s to Item [%d]=%s\n", filenamein, locationfound, listOfFiles[locationfound]->d_name); }
			   retVal = true;
               strcpy(matchname,listOfFiles[locationfound]->d_name); // the the first match
		       j = numberFound;  // break the loop
		   }
		}	
        free(listOfFiles);
    }
	return retVal;
}

bool LookForFileMatchInPath( char * filenamein, char * matchname) {
    // hunts for a match anywhere in the directory listings of PATH to find an equal value.  If PATH is corrupt, 
	// it will stop searching PATH and generate an error statement but try to continue to search if possible.
	// get PATH
	bool retVal = false;
	char pathcopy[MAXFILENAMELEN] = "";           // copies the PATH variable to not edit it accidentally
	char * pathsubname;
	bool stopSearch = false;                      // set to true when a match has been found
	char pathMatchName[MAXFILENAMELEN] = "";      // this is what name was matched to filenamein as it can be a wildcard match
	bool result;                                  // output from any function call 
	                                              // switched over to a split call like result=strtok(pathcopy,": ") and while 
												  // see https://man7.org/linux/man-pages/man3/strtok.3.html
	if (access(filenamein, F_OK|X_OK) == 0) {     // check to see if this file exists...
	    strcpy(matchname, filenamein);  // if it does, use the current name as it is good
        if (DEBUGEXECCMDEXTRA) { printf("Found and can execute %s so returning\n", matchname); }
	    return true;
	}
	if (DEBUGEXECCMDEXTRA) { printf("Searched for %s and matched %s with t/f of %d\n", filenamein, pathMatchName, result); }
	result = runGetVariable("PATH", pathcopy);
	if (DEBUGEXECCMDEXTRA) { printf("PATH is %s and result of %d\n", pathcopy, result); }
	if (result) { // found it so now time to read it, it is : delimited
	   pathsubname=strtok(pathcopy,":");
	   while ((pathsubname != NULL) && (!stopSearch)){                                   // call the search
           if (DEBUGEXECCMDEXTRA) { printf(" looking for matches in directory %s\n", pathsubname); }
           result = LookForFileMatchHere( &pathsubname[0], filenamein, pathMatchName);    // is there a match in this directory?
           if (result) {                                                                  // found the match
               if (DEBUGEXECCMDEXTRA) { printf("pathsubname is %s pathMatchName is %s filenamein is %s\n", pathsubname, pathMatchName, filenamein); }
               strcpy(matchname, pathsubname);                     // bulid full command string, start by first adding the path
               strcat(matchname, "/");                             // then add the separator
               strcat(matchname, pathMatchName);                   // then add the file name
               stopSearch = true;                                  // terminate the search, break the loop
               if (access(matchname, F_OK|X_OK) == 0) {
                   if (DEBUGEXECCMDEXTRA) { printf("Filename %s was found in $PATH and it is executable.\n", matchname); }
                   retVal = true;                                  // return success
               } else {
                   printf("File %s is not an executable file.\n", matchname);
                   errorDoNotExecute   = true;                     // set variable to stop execution later on
                   retVal              = false;                    // return failure because it is not executable
               }
           } else {
	           pathsubname=strtok(NULL,":");
               if (DEBUGEXECCMDEXTRA) { printf("next pathsubname is %s and filenamein is %s\n", pathsubname, filenamein); }
		   }
	   }
	} else {
	   printf("PATH environment variable was not found.\nMany things are not going to work...\n");
	   errorDoNotExecute = true;                                      // don't execute because there won't be any paths to execute against...
	   retVal = false;
	}
	
	return retVal;
}

void EraseAllPendingCommands( void ) {
    int x, j;
	for (j = 0; j < MAXCOMMANDS; ++ j) {                  // loop all commands that can be in the table
	   for (x = 0; x < MAXPARAMETERS; ++x) {              // then loop all parameters that can be in each command
	     strcpy(commandParsing[j].params[x], "");         // set all paremters in each command to nothing ("")
	   }
	   strcpy(commandParsing[j].command , "");            // set the current command to nothing ("")
	   commandParsing[j].parameter_count = 0;             // reset to no parameters in the table, always 1 greater than last parameter
	   commandParsing[j].pipefd[0]       = -1;            // pipeline associated with this command
	   commandParsing[j].pipefd[1]       = -1;            // pipeline associated with this command
	}
	commandParsingIndex = 0;                              // reset to no commands in the command table, always 1 greater than last command
    backgroundSet       = false;                          // reset to false to not put the next command in the background
	errorDoNotExecute   = false;                          // reset to false to allow command to execute
	builtin_fd_in       = -1;                             // value -1 means no file or redirection was asked for by user
    builtin_fd_out      = -1;                             // value -1 means no file or redirection was asked for by user
    builtin_fd_err      = -1;                             // value -1 means no file or redirection was asked for by user
}

bool CheckAndCorrectCommandsPending( void ) {
    // checks all pending commands to see if they can be executed...
	int x;
	bool retVal = true;
	bool searchCommand;
	char commandWithPath[MAXFILENAMELEN] = "";
	for(x = 0; x < commandParsingIndex; ++x) {                                          // correct each command one at a time
	                                                                                    // check to see if this command exists and get it's path updated
	   searchCommand = LookForFileMatchInPath( &commandParsing[x].command[0], &commandWithPath[0]);
	   //if (DEBUGEXECCMD) {printf("Searched for %s and received %s with t/f result %d\n", commandParsing[x].command, commandWithPath, searchCommand); }
       if (searchCommand == false) {
	      printf("Command %s not found.\n", commandParsing[x].command);                 // notify user command was not found
	      retVal              = false;                                                  // failed to correct all commands
		  errorDoNotExecute   = true;                                                   // command not found so don't execute 
	   } else {                                                                         // update the command with the full path to the command to be executed
	      strcpy(&commandParsing[x].command[0], &commandWithPath[0]);
       }
	}
	return retVal;  // false if some command cannot be executed, true if all are executable
}
char* clearQuotes(char* parameter){
    char temp[MAXALIASLENGTH];
	int lastchar;
	strcpy(&removeQuotes[0], parameter);
	if (removeQuotes[0] == '\"') {
	   strcpy(&temp[0], &removeQuotes[1]);
	   strcpy(&removeQuotes[0], &temp[0]);
	   lastchar = (int)strlen(removeQuotes)-1;
	   if (removeQuotes[lastchar] == '\"') {
	       removeQuotes[lastchar] = 0;
	   }
	}
	strcpy(parameter, removeQuotes);
}

bool ExecuteOneCommand( int cmd_num ) {
    // Executes one command at a time
    char clearQ[MAXALIASLENGTH];
    pid_t processid = 0;                                                         // when forking, capture the process ID
    char* arguments[MAXPARAMETERS+1];                                            // build up an array of arguments to pass to execv()
	int x;                                                                       // for counting
	bool retVal = true;                                                          // for return value

	if (DEBUGFORKINGCOMMANDS) {printf(" Executing one command\n");}
	
	arguments[0] = commandParsing[cmd_num].command;                              // first argument is command, ie. "/usr/bin/ls"
	                                                                             //   therefore argument[1] is really first argument
	for (x = 0; x < MAXPARAMETERS; ++x) {                                        // rest of the parameters were captured in yacc above
	  if (strcmp(commandParsing[cmd_num].params[x], "") != 0) {                  // for each parametre, compare to NULL, last parameter
	      arguments[x+1] = clearQuotes(commandParsing[cmd_num].params[x]);       // copy it if it isn't NULL
	  } else {
	      arguments[x+1] = NULL;                                                 // add one more as NULL to terminate
	  }
	}
	
	if (DEBUGFORKINGCOMMANDS) {printf(" Going to fork next.\n");}
	
	if ((processid = fork()) == 0) {
	    if (DEBUGFORKINGCOMMANDS) { printf("This is the Child running %s as process %d command num %d index %d\n", commandParsing[cmd_num].command, processid, cmd_num, commandParsingIndex); }
		if ((cmd_num < (commandParsingIndex-1)) && (commandParsingIndex > 1)) {   // first command and there is more than one command
	        if (DEBUGFORKINGCOMMANDS) { printf("Closed %d from pipefd[0] %d pipefd[1] %d pipe 1a\n", cmd_num , commandParsing[cmd_num].pipefd[0], commandParsing[cmd_num].pipefd[1]); }
		    dup2(commandParsing[cmd_num].pipefd[1], STDOUT_FILENO);               // copy the write  side pipefd[1] 
			close(commandParsing[cmd_num].pipefd[0]);                             // close the read  side pipefd[0] (reverse below to prevent deadlock)
			close(commandParsing[cmd_num].pipefd[1]);                             // close the write side pipefd[1] 
		}
		if (cmd_num == 0) {                                                       // first command, process input file if present
		    if (builtin_fd_in >= 0) {                                             // if >=0, a file was opened, and should be used
	            if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stdin from a file.\n"); }
		        dup2(builtin_fd_in, STDIN_FILENO);
            }				
		}                                                                          // next do all the File I/O connections
		if (cmd_num == (commandParsingIndex-1)) {                                  // last command, process all output file items
		    if (DEBUGFORKINGCOMMANDS) { printf("Checking for redirections.\n"); }
		    if (builtin_fd_out >= 0) {                                             // if >=0, a file was opened, and should be used
	            if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stdout to file.\n"); }
		        dup2(builtin_fd_out, STDOUT_FILENO);
            }				
		    if (builtin_fd_err >= 0) {                                             // if >=0, a file was opened, and should be used
	            if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stderr to file.\n"); }
		        dup2(builtin_fd_err, STDERR_FILENO);
            }				
		    if (builtin_fd_err == -2) {                                            // special value of -2 is a redirect stderror to stdout
	            if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stderr to stdoutf.\n"); }
		        dup2(STDOUT_FILENO, STDERR_FILENO);
            }				
		}
		if ((cmd_num >= 1) && (commandParsingIndex > cmd_num)) {                   // next command's last pipe connection 
		    dup2(commandParsing[cmd_num-1].pipefd[0], STDIN_FILENO);               // copy  the read  side
			close(commandParsing[cmd_num-1].pipefd[1]);                            // close the write side (reverse of above to prevent deadlock)
			close(commandParsing[cmd_num-1].pipefd[0]);                            // close the read  side
	        if (DEBUGFORKINGCOMMANDS) { printf("Closed %d from pipefd[0] %d pipefd[1] %d pipe 2\n", cmd_num-1 , commandParsing[cmd_num-1].pipefd[0], commandParsing[cmd_num-1].pipefd[1]); }
		}
	    execv( commandParsing[cmd_num].command, arguments );                       // replace nutshell image with command to run
		if (DEBUGFORKINGCOMMANDS) {printf(" Fork FAILED.\n");}
    } else {
		if ((cmd_num >= 1) && (commandParsingIndex > cmd_num)) {
           if (DEBUGFORKINGCOMMANDS) { printf("This is the Parent running as %d %d %d\n", processid, commandParsing[cmd_num-1].pipefd[1], commandParsing[cmd_num-1].pipefd[0]); }
		   close(commandParsing[cmd_num-1].pipefd[0]);                              // close the parent read  side pipefd[0]
		   close(commandParsing[cmd_num-1].pipefd[1]);                              // close the parent write side pipefd[1]
		}
	}
	return retVal;
}

void ExecuteAllCommandsPending( void ) {                                    // lots of hours spend figuring this out, don't change
    bool validCommands;                                                     // turn all command names to full path names 
    validCommands = CheckAndCorrectCommandsPending();                       // "ls" becomes "/usr/bin/ls" if in PATH
	if ((errorDoNotExecute == false) && (validCommands == true)) {          // validCommands is true if all commands work
	    for(int x = 0; x < commandParsingIndex; ++x) {                      // for every command from left to right... producer to consumer..
		   if (DEBUGEXECCMD) {printf(" Launching command %d of [%s]\n", x, commandParsing[x].command);}
		  ExecuteOneCommand(x);                                             // run the command using fork(), execv(), pipes
		}
	}
	if (DEBUGEXECCMD) {printf(" Commands entering waiting phase.\n");}
	if (!backgroundSet) {                                                       
	    for(int x = 0; x < commandParsingIndex; ++x) {                      // wait for all spun up children to terminate
	       wait(NULL);                                                      // this waits for a child, any child....
	    }                                                                   // in nutshell.c see main() for background clearing
	} 
	if (DEBUGEXECCMD) {printf(" Commands completed after all launched.\n");}
	EraseAllPendingCommands();          // clear the pending commands and start over
}

void runBackgroundOp( void ) {
   backgroundSet = true;
}

int runStringFoundCommand( char* arg){                                // a command string was found by yacc above
   if(DEBUGPARSER){printf("found Command string, [%s]\n", arg);}
   strcpy(commandParsing[commandParsingIndex].command , arg);         // add the new command
   if (commandParsingIndex > 0) {                                     // this will be the second command, a pipe() is Needed
      pipe(commandParsing[commandParsingIndex-1].pipefd);             // create the pipeline for one to another
   }
   commandParsingIndex++;                                             // increment the command count
   return 1;
}

int runStringFoundParameters( char* arg){                             // a parameter string was found by yacc above
   if(DEBUGPARSER){printf("found Parameters string, [%s]\n", arg);}   // test just in case there is a mistake in parsing...
   if (commandParsingIndex > 0) {                                     // parameters SHOULD not be found unless command was found,
      strcpy(commandParsing[commandParsingIndex-1].params[commandParsing[commandParsingIndex-1].parameter_count], arg);
      commandParsing[commandParsingIndex-1].parameter_count++;        // increment this command's number of parameters
   }
   return 1;
}

void RedirectStdOutAppendCommandParsing( char * redirectLocation ) {     
   builtin_fd_out = open(redirectLocation, O_WRONLY|O_APPEND);           // write only appending file for std out
   if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stdout to file builtin_fd_out is %d.\n", builtin_fd_out); }
   if (builtin_fd_out == -1) { // failed 
      printf("Unable to write appended to standard out to %s.\n", redirectLocation);
	  errorDoNotExecute   = true;
   }
}

void RedirectStdOutCommandParsing( char * redirectLocation ) {     
   builtin_fd_out = open(redirectLocation, O_WRONLY|O_CREAT, 0666);      // write only std out file
   if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stdout to file builtin_fd_out is %d.\n", builtin_fd_out); }
   if (builtin_fd_out == -1) { // failed 
      printf("Unable to write standard out to %s.\n", redirectLocation);
	  errorDoNotExecute   = true;
   }
}

void RedirectStdErrCommandParsing( char * redirectLocation ) {
   builtin_fd_err = open(redirectLocation, O_WRONLY|O_CREAT, 0666);      // write only error out, new file
   if (builtin_fd_err == -1) { // failed 
      printf("Unable to write error out to %s.\n", redirectLocation);
	  errorDoNotExecute   = true;
   }
}

void RedirectStdInCommandParsing( char * redirectLocation ) {
   builtin_fd_in = open(redirectLocation, O_RDONLY);                     // read only input file
   if (builtin_fd_in == -1) { // failed 
      printf("Unable to read standard in from %s.\n", redirectLocation);
	  errorDoNotExecute   = true;
   }
}

void runStringFoundRedirect( char* arg, int redirect_out_capture) {             // all the redirects come here with the differe
   if(DEBUGPARSER){printf("Redirecting [%s] on 1 ", arg);}                      // each opens a file for the right purpose
   if(DEBUGPARSER){printf("Redirecting [%s] on 2 ", arg);}                      // each opens a file for the right purpose
   switch (redirect_out_capture) {
      case REDIRECTSTDOUT : RedirectStdOutCommandParsing( arg );                // open file for write new file for std out
	                        if(DEBUGPARSER){printf("REDIRECTSTDOUT\n");}         
                            break;
      case REDIRECTERROUT : 
	                        RedirectStdErrCommandParsing( arg );                // open file for write new file for error out
	                        if(DEBUGPARSER){printf("REDIRECTERROUT\n");}
                            break;
      case REDIRECTSTDOUTAPPEND : 
	                        RedirectStdOutAppendCommandParsing( arg );          // open file for write appending file for std out
	                        if(DEBUGPARSER){printf("REDIRECTSTDOUTAPPEND\n");}
                            break;
      case REDIRECTSTDIN :  
	                        RedirectStdInCommandParsing( arg );                 // open file for read file for std in
	                        if(DEBUGPARSER){printf("REDIRECTSTDIN\n");}
                            break;
	  case REDIRECTERROUTSTDOUT :                                               // no file just a redirect special value for later
	                        builtin_fd_err = -2;                                // special value for redirection of this type
	                        if(DEBUGPARSER){printf("REDIRECTERROUTSTDOUT\n");}
                            break;
      default: break;
   }
}

int runGetAlias(char *name, char *destinationword) {
    // takes in name and returns word copied to the destination destinationword
    int retVal = -1;
	for (int i = 0; i < varIndex; i++) {
        if(strcmp(aliasTable.name[i], name) == 0) {
		    strcpy(destinationword, aliasTable.word[i]);
			retVal = i;
			break;
		}
	}
	return retVal;
}

bool CheckLoop(char *word, char *name) {
   char foundWord[MAXALIASLENGTH];
   char nextWord[MAXALIASLENGTH];
   int  locationFound;
   bool done = false;
   bool loopfound = false;
   locationFound = runGetAlias(name, foundWord);
   while (locationFound >= 0)  {
      if (strcmp(word, foundWord) == 0) {  // matched and a cycle
         return true;
      }
      strcpy(nextWord, foundWord);
      locationFound = runGetAlias(nextWord, foundWord);
   }
   return false;
}

int runSetAlias(char *name, char *word) {
	for (int i = 0; i <= aliasIndex; i++) {
       if (((int)strcmp(name, word)) == 0){
			printf("Error, expansion of \"%s\" would create a loop.\n", name);
			return 1;
		}
		else if (CheckLoop(name, word)) {  // returns true if there is a loop
			printf("Error, expansion of \"%s\" would create a loop.\n", name);
			return 1;
		}
		else if(strcmp(aliasTable.name[i], name) == 0) {
			strcpy(aliasTable.word[i], word);
			return 1;
		}
	}
	strcpy(aliasTable.name[aliasIndex], name);
	strcpy(aliasTable.word[aliasIndex], word);
	aliasIndex++;
	return 1;
}

int runPrintAlias(void) {
	int i;
	char aliasOut[MAXALIASLENGTH];
	for (i = 0; i < aliasIndex; i++) {  // search for the alias
		if (builtin_fd_out >= 0) {                                                // if >=0, a file was opened, and should be used
	        if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stdout to file builtin_fd_out is %d.\n", builtin_fd_out); }
			sprintf(aliasOut, "%s=%s\n",aliasTable.name[i], aliasTable.word[i] ); // write to the internal buffer
			write(builtin_fd_out, aliasOut, strlen(aliasOut));                    // write to the file
        }   else {
    		printf("%s=%s\n",aliasTable.name[i], aliasTable.word[i] );            // OR write to the screen same data
		}
	}
	EraseAllPendingCommands();                                                    // resets the output designators for next parse
	return 1;
}

int runUnsetAlias(char *name) {
    bool foundit = false;
	int i;
	int j;
	for (i = 0; (i < aliasIndex) && (!foundit); i++) {  // search for the alias
	    if (DEBUGMODEUNALIAS) {
	       printf("checking aliasTable.name[%d] = %s is equal to %s\n", i, aliasTable.name[i], name ); }
		if(strcmp(aliasTable.name[i], name) == 0) {
		    foundit = true;
		}
	}
	if (DEBUGMODEUNALIAS) {
	   printf("unalias found match t/f %d at %d\n", foundit, i ); }
	if (foundit == true) {                          // if alias existed, remove it from list
	    for (j = i-1; j < (aliasIndex-1); j++) {
	       strcpy(aliasTable.name[j], aliasTable.name[j+1]);
	       strcpy(aliasTable.word[j], aliasTable.word[j+1]);
		}
	    aliasIndex--;  // decrement count
	} else {
	    printf("No match for alias %s was found.\n", name);
	}
	return 1;
}

int runSetVariable(char *varname, char *word) {
    if (DEBUGMODESETVARIABLE) { printf("attempting to set %s = %s\n", varname, word); }
	for (int i = 0; i < varIndex; i++) {
		if(strcmp(varname, word) == 0){
			printf("Error, definition of \"%s\"would create a loop of environment variables 1.\n", varname);
			return 1;
		}
		else if(strcmp(varTable.var[i], varname) == 0) {
            if(strcmp(varname, "PWD") == 0) {
                printf("Unfortunately, you can not change the variable \"PWD\"in this shell.\n");
                return 1;
            }
            if(strcmp(varname, "HOME") == 0) {
                printf("Unfortunately, you can not change the variable \"HOME\"in this shell.\n");
                return 1;
            }
			strcpy(varTable.word[i], word);
			return 1;
		}
	}
	strcpy(varTable.var[varIndex], varname);
	strcpy(varTable.word[varIndex], word);
	varIndex++;

	return 1;
}

bool runGetVariable(char *varname, char *destinationword) {
    // takes in varname and returns word copied to the destination destinationword
    bool retVal = false;
    if (DEBUGMODEGETVARIABLE) {
       printf("attempting to find %s environment variable.\n", varname); }
	for (int i = 0; i < varIndex; i++) {
        if(strcmp(varTable.var[i], varname) == 0) {
		    strcpy(destinationword, varTable.word[i]);
			retVal = true;
		}
	}
	return retVal;
}

int runPrintEnv(void) {
	int i;
	char aliasOut[MAXALIASLENGTH];
	for (i = 0; i < varIndex ; i++) {                                          // search for the variables
		if (builtin_fd_out >= 0) {                                             // if >=0, a file was opened, and should be used
	        if (DEBUGFORKINGCOMMANDS) { printf("Redirecting stdout to file builtin_fd_out is %d.\n", builtin_fd_out); }
			sprintf(aliasOut, "%s=%s\n",varTable.var[i], varTable.word[i] );   // write to the internal buffer
			write(builtin_fd_out, aliasOut, strlen(aliasOut));                 // write to the file
        }   else {                                                          
    		printf("%s=%s\n",varTable.var[i], varTable.word[i] );              // OR write to the screen same data
		}
	}
	EraseAllPendingCommands();                                                 // resets the output designators for next parse
	return 1;
}


int runUnsetVariable(char *varname) {
    bool foundit = false;
	int i;
	int j;
	for (i = 0; (i < varIndex) && (!foundit); i++) {  // search for the alias
	    if (DEBUGMODEUNVARIABLE) {
	       printf("checking varTable.var[%d] = %s is equal to %s\n", i, varTable.var[i], varname ); }
		if(strcmp(varTable.var[i], varname) == 0) {
		    foundit = true;
			if(strcmp(varTable.var[i], "HOME") == 0) {
	           printf("Unfortunately, you can not unset the variable \"HOME\"in this shell.\n");
			   return 1;
			   }
			if(strcmp(varTable.var[i], "PATH") == 0) {
	           printf("Unfortunately, you can not unset the variable \"PATH\"in this shell.\n");
			   return 1;
			   }
			if(strcmp(varTable.var[i], "PWD") == 0) {
	           printf("Unfortunately, you can not unset the variable \"PWD\"in this shell.\n");
			   return 1;
			   }
		}
	}
	if (DEBUGMODEUNVARIABLE) {
	   printf("unalias found match t/f %d at %d\n", foundit, i ); }
	if (foundit == true) {                          // if alias existed, remove it from list
	    for (j = i-1; j < (varIndex-1); j++) {
	       strcpy(varTable.var[j], varTable.var[j+1]);
	       strcpy(varTable.word[j], varTable.word[j+1]);
		}
	    varIndex--;  // decrement count
	} else {
	    printf("No match for alias %s was found.\n", varname);
	}
	return 1;
}

