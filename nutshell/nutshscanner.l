%{
// Date:     April 14, 2021
// Class:    COP 4600
//           University of Florida
//           Team 145
// Team Members Greg Bolling & Jovencey StFleur
// Semester: Spring 2021
// File      nutshscanner.l
//
// Implements:  Nutshell Project
//              Holds the flex / lex input for the parser.  Defines the commands that can be executed and
//              handles the replacement of aliases and environment variables before sending them to the 
//              yacc / bison side.  It reverses the alias by unput commands.
//
// This began as a demo micro-shell and has been greatly expanded.  Many thanks to the UF TA staff for the starting point
// that has grown to become a much larger shell.  The commands implemented are from the assignment and grew slowly
// until it reached completion.  The starting point of parsing with flex/bison was much appreciated.
//
#include "nutshparser.tab.h"
#include <string.h>
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
#include "global.h"

bool skip_next_alias = false;
bool first_string_seen = false;
bool runGetVariable(char *varname, char *destinationword);
char* clearQuotes(char* parameter);


bool TestWildcardMatchIgnorePath( char * wildcardin, char * exactnamein) {   // fnmatch does an automatic pattern match in regex-like    
  bool retVal = false;
  if (fnmatch( wildcardin, exactnamein, FNM_PERIOD | FNM_PATHNAME ) == 0) {  // see https://www.gnu.org/software/libc/manual/html_node/Wildcard-Matching.html
     retVal = true;
  }
  return retVal;
}

void SplitPathFilename(char * directory, char * filename, char * start) {  // takes in start, splits into path and filename
    int x;
	int incominglen;
	bool pathseen = false;
	char tempDirectory[MAXFILENAMELEN] = "";                
	char tempFilename[MAXFILENAMELEN] = "";
	incominglen = (int) strlen(start);
	char temp[2];
	temp[1] = 0;
	for(x = incominglen -1; x >= 0; x--) {                                 // Reverse search string for "/"
	// if (((start[x] != '/') && (start[x] != '.')) && (pathseen == false)) {  // core dumped path with bad split on "f?.txt"
	   if ((start[x] != '/') && (pathseen == false)) {                    // copy the right most characters as the filename
	      temp[0] = start[x];                                             // characters will be in reverse, can reverse below
		  strcat(tempFilename, temp);
	   } else {                                                           // after first '/' is seen, add to the Path
	      pathseen = true;                                                // path will be in reverse, can reverse below
	      temp[0] = start[x];
		  strcat(tempDirectory, temp);
	   }
	}
	strcpy(filename, "");                                                 // need to reverse the filename "llehstun" to "nutshell"
	incominglen = (int) strlen(tempFilename);
	for(x = incominglen-1; x >= 0; x--) {
	      temp[0] = tempFilename[x];
		  strcat(filename, temp);
	}
	strcpy(directory, "");                                               // need to reverse the path "/nib/rsu/" to "/usr/bin/
	incominglen = (int) strlen(tempDirectory);
	for(x = incominglen-1; x >= 0; x--) {
	      temp[0] = tempDirectory[x];
		  strcat(directory, temp);
	}                                                                    // the results are in directory and filename
}

bool NeedsWilidcardExpanding( char* InputParameter) {      // does this string have a * or ? in it?
    int x;
	int incominglen;
	bool retVal = false;
	incominglen = (int) strlen(InputParameter);
	for(x = 0; x < incominglen; x++) {
	   if ((InputParameter[x] == '*') || (InputParameter[x] == '?')) {  // look for * or ?
	     retVal = true;
	   }
	}
	return retVal;
}

void ExpandWildcardString(char * directory, char* InputParameter) {
    struct passwd* pwd;
	char expandedFiles[MAXFILENAMELEN] = "";
	char file[MAXFILENAMELEN]          = "" ;
	int numberFound;
	int locationfound = 0;
	struct dirent **listOfFiles;                                                 // so listOfFiles[0]->d_name has the first file name, etc...
	if ((int)strlen(directory) == 0) {
        numberFound = scandir("./", &listOfFiles, NULL, alphasort);              // for when there isn't a directory defined
	} else 
	if (directory[strlen(directory)-1] == '/') {                                 // has to be a valid directory or it will fail
        numberFound = scandir(directory, &listOfFiles, NULL, alphasort);         // get the files in a list and the total count
	}
    if (numberFound > 0) {                                                       // no files were found that match the file or error...
	   for(int j = 0; j < numberFound; ++j) {  
	      if (TestWildcardMatchIgnorePath( InputParameter, listOfFiles[j]->d_name)) {
            strcat(expandedFiles,directory);                                     // the directory part first
            strcat(expandedFiles,listOfFiles[j]->d_name);                        // then the first match
            strcat(expandedFiles," ");                                           // then a separator for the next match
	      }
	   }	
       free(listOfFiles);
	   strcpy(InputParameter, expandedFiles);
   }
}


bool varExpand(char * source){   // looks for variables and replaces them
                                 // Example: ${NAME} anywhere in the string will get replaced
								 // if it can be found by runGetVariable. so "go ${HOME}" becomes "go /home/myuser"
    char CopySource[256];
    char VariableIn[256] = "";
    char VariableReplace[256];
    char Result[256] = "";
    int  sourceLength;
	bool retVal = false;
	int  x;
				   
    bool  foundDollar = false;                                     // was a $ found True/False?
    bool  foundOpen = false;                                       // was a { found True/False?
    char  tempstr[2];                                              // Helps build up strings of one character to be appended

    tempstr[1] = 0;                                                // use this to concatenate characters to strings
	strcpy(CopySource, source);                                    // backup the source string
	sourceLength = (int) strlen(source);                           // get the length of the source
				   
    for(x = 0; x < sourceLength; ++x) {                            // go through every character in this string
        if (((CopySource[x] != '}') && (foundDollar == true)) && (foundOpen == true))  {  // add until } shows up
            tempstr[0] = CopySource[x];
            strcat(VariableIn, tempstr);
        } else
        if (CopySource[x] == '$') {                                // is this character the $?
            foundDollar = true;                                    // found the first character, $
            foundOpen = false;                                     // { has been seen yet
            strcpy(VariableIn, "");                                // clear the VariableIn name
        } else
        if ((CopySource[x] == '{') && (foundDollar == true)) {     // ${ have now been seen 
            foundOpen = true;                                      
        } else
        if (((CopySource[x] == '}') && (foundDollar == true)) && (foundOpen == true)) { // replace variable
            if(!runGetVariable(VariableIn, VariableReplace)) {                         // go get VariableReplace
                printf("Unable to locate variable [%s]\n", VariableIn);
            } else {
                strcat(Result, VariableReplace);
				retVal  = true;
            }
            foundDollar = false;                                   // reset to start state
            foundOpen   = false;                                   // reset to start state
        } else {                                                   // if it gets here, no variable sequence, just copy string
            tempstr[0] = CopySource[x];                            // bulid a single character string such as "t"
            strcat(Result, tempstr);                               // append to the result because no replacement needed here
        }
    }
	strcpy(source, Result);                                        // send the result back
	return retVal;
}

int tildeExpansion( char * source){                                          // performs tilde expansion and returns back to source
    struct passwd* pwd;                                                      // structure to get user information
	char *tokenized;                                                         // catches output of strtok() parsing for '/'
	char userDirectory[MAXFILENAMELEN];                                      // directory for a given user
	char userName[MAXFILENAMELEN];                                           // user name for "~username/" expansion
	char sourceCopy[MAXFILENAMELEN];                                         // make copy of source because using it in strtok()
	char destination[MAXFILENAMELEN];                                        // final assembled result, copied back to source
	
	pwd = getpwuid(getuid());                                                // get system to tell who this user is?
	strcpy(userDirectory, pwd->pw_dir);                                      // copy this user's directory path to userDirectory
	if ((source[0] == '~') && ((source[1]=='\0')||(source[1]=='/')))  {      // if this was just a "~" find home directory and change
	    strcpy(destination, userDirectory);                                  // start with the user's directory and add the rest
		strcat(destination, source+1);                                       // add incoming string after '~' character 
		strcpy(source, destination);
		return 1;
	}
	if (source[0] == '~') {                                                  // if it made it here it was not "~" but maybe "~user"
	    strcpy(sourceCopy, source);
		tokenized = strtok(sourceCopy, "/");                                 // grab the whole word
		strcpy(userName, tokenized+1);                                       // remove the "~" in the front
		pwd = getpwnam(userName);                                            // and ask system who is this user?
		if (pwd == NULL) {                                                   // if system can't find this user...
            printf("Cannot find UID for name 2 %s\n", userName);               // state an error and notify user
			return 1;
		} else {                                                             // else the user was found...
		    strcpy(destination, pwd->pw_dir);                                // got the directory, now attach rest of string
			strcat(destination, &source[0]+(int)strlen(tokenized));          // add the rest of the path
	        strcpy(source, destination);
			return 1;
		}
	}
	return 1;                                                                // no tilde, just return same string
}

char* subAliases(char* name){
    char temp[MAXALIASLENGTH];
	int lastchar;
    for (int i = 0; i < aliasIndex; i++) {                                  // aliases are stored with the "" but have to
	    if (DEBUGPARSER)  {                                                 
	        printf("subalias table [%d] name = %s  word = %s\n", i, aliasTable.name[i], aliasTable.word[i]); }
        if(strcmp(aliasTable.name[i], name) == 0) {                         // be corrected when they are found
		    strcpy(&removeQuotes[0], aliasTable.word[i]);                   // if quotes exist on the end, remove them
			if (removeQuotes[0] == '\"') {                                  // if first character is a "
		       strcpy(&temp[0], &removeQuotes[1]);                          // copy over it from one less character
		       strcpy(&removeQuotes[0], &temp[0]);                          // and put back to the source character
			   lastchar = (int)strlen(removeQuotes)-1;                      // get index for last character
			   if (removeQuotes[lastchar] == '\"') {                        // and remove last character
		           removeQuotes[lastchar] = 0;                              // zero to terminate the string of characters
			   }
			}
            return removeQuotes;
        }
    }
    return name;
}
bool ifAlias(char* name){
    for (int i = 0; i < aliasIndex; i++) {
	    if (DEBUGPARSER) {
	        printf("ifalias table [%d] name = %s\n", i, aliasTable.name[i]); }
        if(strcmp(aliasTable.name[i], name) == 0) {
            return true;
        }
    }
    return false;
}
%}
%array
%option noyywrap
%x string_condition
%x my_new_string
                   // had to make a lot of changes as problems happened, strings adding :, {}, 
				   // had to split to new ANYCHAR2 because some strings have '" this "' meaning its a different
				   // string.  Wouldn't work after hours of trying with one string from ANYCHAR.
CHAR               [:{}${}?*~.A-Za-z0-9!\/_-][:{}${}?*~.A-Za-z0-9!\/_-]*
ANYCHAR            [:{})(*%$#@!`;,\.a-zA-Z0-9'/*_=~ -][:{})(*%$#@!`;,\.a-zA-Z0-9'/*_=~ -]*
ANYCHAR2           [:{})(*%$#@!`;,\.a-zA-Z0-9/*_=~ -\"][:{})(*%$#@!`;,\.a-zA-Z0-9/*_=~ -\"]*

%%

<string_condition>{ANYCHAR}+    { 
                                  strcpy(buildUpString2, yytext); 
					              varExpand(buildUpString2);             // replace any variables that need to be replaced
                                  strcpy(yytext, buildUpString2); 
					              strcpy(buildUpString2, "\"");
                                  strcat(buildUpString2, yytext); 
                                  strcat(buildUpString2, "\""); 
                                  strcpy(yytext, buildUpString2); 
                                  yylval.string = strdup(yytext); 
								  return STRING;}
<string_condition>[\"]          { BEGIN(INITIAL);}
<string_condition>[\n]          { BEGIN(INITIAL); return END;}
<my_new_string>{ANYCHAR2}+      { yylval.string = strdup(yytext); return STRING;}
<my_new_string>[\']             { BEGIN(INITIAL);}
<my_new_string>[\n]             { BEGIN(INITIAL); return END;}

[ ]		            { }
bye                 { return BYE; }
cd		            { return CD;}
alias		        { first_string_seen = true;  skip_next_alias = true; return ALIAS; }     // once a word seen, skip replacements alias below
setenv		        { first_string_seen = true;  skip_next_alias = true; return SETENV; }
unsetenv		    { first_string_seen = true;  skip_next_alias = true; return UNSETENV; }
printenv	        { first_string_seen = true;  skip_next_alias = true; return PRINTENV; }
unalias		        { first_string_seen = true;  skip_next_alias = true; return UNALIAS; }
"\n"		        { first_string_seen = false; skip_next_alias = false; return END; }      // reset alias replacement back to normal
"|"   		        { return PIPE; }
">"   		        { return REDIRECTSTDOUT; }
">>"  		        { return REDIRECTSTDOUTAPPEND; }
"1>" 		        { return REDIRECTSTDOUT; }
"2>" 		        { return REDIRECTERROUT; }
"&" 		        { return BACKGROUNDOP; }
"&1"		        { return REDIRECTERROUTSTDOUT; }
"<" 		        { return REDIRECTSTDIN; }
[\']                { BEGIN(my_new_string); }
[\"]                { BEGIN(string_condition); }
{CHAR}+             {                                   
                       strcpy(buildUpString, yytext);   // make a copy of the incoming token
					   tildeExpansion(buildUpString);   // try to expand the tilde if that's what at the front
					   if (varExpand(buildUpString)) {  // replace any variables that need to be replaced
					       clearQuotes(buildUpString);  // in case there are quotes 
					       strcpy(yytext, buildUpString);   // copy the result back into the source
                           char *yycopy = strdup( buildUpString );
	                       if (DEBUGPARSER) {printf("Variable Expansion back to %s\n", yycopy); }  
                           for ( int i = strlen(buildUpString) - 1; i >= 0; --i )
                                 unput( yycopy[i] );
                           free( yycopy );
					   } else {
					       strcpy(yytext, buildUpString);   // copy the result back into the source
                           if ((first_string_seen == true) && (NeedsWilidcardExpanding(yytext))) {  // if a parameter and 
                               SplitPathFilename(&splitDirectory[0], &splitFilename[0], yytext);    // it has a * or ? in word
                               ExpandWildcardString(splitDirectory, splitFilename);                 // expands the file names
                               char *yycopy = strdup( splitFilename );                              // Push result back to input
                               for ( int i = strlen(splitFilename) - 1; i >= 0; --i )               // reverse order push
                                     unput( yycopy[i] );                                            // puts characters back in
                               free( yycopy );                                                      // release allocated form strdup() above
                               skip_next_alias = true;                                              // don't expand aliases
                               first_string_seen = true;                                            // don't re-replace strings
                           } else {                                                                 // alias expansion occurs here
                               if (skip_next_alias == false) {                                      // don't repeat replacing - infinite loop
                                   if(ifAlias(yytext)) {                                            // is this an alias item?
                                      char *yycopy = strdup( subAliases(yytext) );                  // Push result back to input
                                      for ( int i = strlen(subAliases(yytext)) - 1; i >= 0; --i )   // reverse order push
                                            unput( yycopy[i] );                                     // puts characters back in
                                      free( yycopy );                                               // release allocated form strdup() above
                                   } else {				
                                      yylval.string = strdup(yytext);                               // copy the string
                                      skip_next_alias = true;                                       // skip another alias
                                      first_string_seen = true;                                     // next strings are parameters
                                      return STRING;
                                   };
					           } else {      // No aliases expand after first command until end is reached					       			
	                               if (DEBUGPARSER) {printf("yytext: %s bottom 2\n", yytext); }     // copy string and return to parser
                                   yylval.string = strdup(yytext);
                                   skip_next_alias = true; 
                                   return STRING;
                                   first_string_seen = true; 
					           }
						   }
					   }
                    } 
%%