#!/usr/bin/env bash

# html2ascii: a simple html to ascii convertor and tokenizer
# usage:      html2ascii [file]
# note:       the html tags (like <p>) will be removed from the file
#             and the html character entities (like &aring;) will be
#             replaced by appropriate characters. The result will be
#             tokenized and the tokens will be shown on standard output.
# 960312 erik.tjong@ling.uu.se

# If no input file specified
if [ -z "$1" ]
then
   # then read input from standard input
   cat
else
   # else read input from the file
   cat $1
fi|\
   #########START TAG REMOVAL CODE#######################################
   # Remove every substring starting with < and ending with > (html tags)
   # [^>]* means zero or more occurences of characters that are
   # different from >
   # sed stands for stream editor and all sed commands in this file
   # 1. replace some string A by another string B (s/A/B/g)
   # 2. Remove every substring starting with < (starts of html tags)
   # 3. Remove every substring ending with > (end of html tags)
   #       1.                2.                3.
   sed -e 's/<[^>]*>//g' -e 's/<[^>]*$//g' -e 's/^[^>]*>//g' |\
   #
   #########START ENTITY REPLACEMENT CODE################################
   # Replace the html character codes by UNIX codes
   # A call of /usr/local/bin/htmlize would have been useful here
   # 1. &aring;  UNIX: octal 345 �
   # 2. &Aring;  UNIX: octal 305 �
   # 3. &auml;   UNIX: octal 344 �
   # 4. &Auml;   UNIX: octal 304 �
   # 5. &ouml;   UNIX: octal 366 �
   # 6. &Ouml;   UNIX: octal 326 �
   #       1.                 2.                 3.
   sed -e 's/&aring;/�/g' -e 's/&Aring;/�/g' -e 's/&auml;/�/g'  \
       -e 's/&Auml;/�/g'  -e 's/&ouml;/�/g'  -e 's/&Ouml;/�/g'  |\
   #       4.                 5.                 6.
   #########START TOKENIZATION CODE######################################
   # Convert every space (' ') to a newline ('\012')
   #
   tr ' ' '\012' |\
   #
   # Words at the end of a sentence have a punctuation mark attatched to
   # them. We will remove those by moving all punctuation marks at the
   # end of lines ($). [\.?,:;!] is any character of the set .?,:;!
   #
   sed 's/[\.?,:;!]$//g' |\
   #
   # Text may contain quotations which means that some words will start
   # with "'`. We will remove all of these. However words may contain a '
   # so we will only remove that token if it is at the beginning or the
   # end of a word.
   # 1. remove all "
   # 2. remove all `
   # 3. remove all ' at the start of a word (prevent removing ' from John's)
   # 4. remove all ' at the end of a word
   #       1.          2.          3.            4.
   sed -e "s/\"//" -e "s/\`//" -e "s/ \' //" -e "s/\' //"
   #
   # The output of this last sed command will be shown on screen

# Done
exit 0
