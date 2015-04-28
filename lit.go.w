# Lit, simple tool for language agnostic literate programming

Literate programming is a technique introduced by Donalad Knuth many years ago. 
Nowadays literate programming is almost dead, it's really sad in my opinion. This little application designed to bring
literate programming approach to almost any programming language expirience.

I strongly recomend to read original Knuth paper on Literate Programming (http://www.literateprogramming.com/knuthweb.pdf)

Noweb.py by Jonathan Aquino was inspiration for this humble peace of code.

## Main idea
It was surprisingly easy to implement this tool. Main idea is to parse file in single pass line-by-line detecting 
chunks and use `Map` to store it's names and values. 
In second part of processing recursively 'expand' chunks bodies, replacing entries of other chunks to get full programm.

## Used packages
To process files this application using os, io, bufio and regex packages. Flag package used to parse command line parameters. It's a bit shitty, but it's ok.

<<Used packages>>=
	"regexp"
	"flag"
	"bufio"
	"fmt"
	"os"
	"io"
	"strings"
@

# Run flow
## Parsing command line parameters

Right after start application will try to parse command line parameters. If some vital data is not defined application will show usage and exit. 
There is 5 overall parameters: 
* --src-out: File name for code output ("tangle" output)
* --doc-out: File name for document output ("weave" output)
* --default-chunk: Default chunk name. Chunk with this name will consider holding main program code. By default it's name is "*"
* --keep-code: lit will include source code chunks in generated documents
* First parameter after all options will be used as name of file to parse

As I mention above, we using `flag` package to parse command line. For every command line argument there is variable defined. Default values for src-out and doc-out parameters are empty strings.
In Go empty string is "zero value" for string, so we can catch situation when user omit one or another parameter. Default value for default-chunk is "*".

<<Command line parsing>>=
	var sourceFile string
	var docFile string
	var parsingFile string
	var defaultChunk string
	var keepSourceCode bool

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage of lit: lit [options] file-to-parse.w\n")
		flag.PrintDefaults()
	}

	flag.StringVar(&defaultChunk, "default-chunk", "*", "Default program chunk")
	flag.StringVar(&sourceFile, "src-out", "", "File to write source code")
	flag.StringVar(&docFile, "doc-out", "", "File to write document")
	flag.BoolVar(&keepSourceCode, "keep-code", false, "Should include source code in documents")
	flag.Parse()
@


# Check command line options validity
If there is no file to parse we can't do anything except show usage. Another case is when both src-out and doc-out is missing. In this situation application will show usage too, because
it can't do anything useful with given file. 

<<Parameters check>>=
	if len(flag.Args()) > 0 {
		parsingFile = flag.Arg(0)
	}
 
	if parsingFile == "" || (sourceFile == "" && docFile == "") {
		flag.Usage()
		os.Exit(0)
	}
@

But if /only one/ of they is missing application can dump source code or documentation without dumping another part.

For exmaple, if you want to generate both, documentation and source from some file `source.w`, you should run:
	
	lit --src-out source.c --doc-out source.tex source.w

But if you need only source, you can omit doc-out parameter:
	
	lit --src-out source.c source.w

Same works for doc-out.

<<Processing command line>>=
	if sourceFile != "" {
		sourceOutput, err := os.Create(sourceFile)
		defer sourceOutput.Close()

		if err != nil {
			panic(err)
		}
		sourceOutput.WriteString(chunks[defaultChunk])
	}

	if docFile != "" {
		docOutput, err := os.Create(docFile)
		defer docOutput.Close()	

		if err != nil {
			panic(err)
		}
		docOutput.WriteString(document)	
	}
@


## File parsing

File parsing process is extremely straightforward. After file is open we reading it line by line trying to match one specified regular expressions.

<<Open file and buf reader>>=
	f, err := os.Open(fileName)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	fileBuf := bufio.NewReader(f)
@

Expression "<<([^>]+)>>=" is used to match beginning of chunk, "^@" for end of chunk.

<<Define regular expressions>>=
	var (
		endOfChunkMatcher *regexp.Regexp
		chunkMatcher *regexp.Regexp
		regexpError error
	)

	chunkMatcher, regexpError = regexp.Compile("<<([^>]+)>>=")
	if regexpError != nil {
		panic(regexpError)
	}

	endOfChunkMatcher, regexpError = regexp.Compile("^@")
	if regexpError != nil {
		panic(regexpError)
	}
@

After chunk beginning is found we extract it's name from submatches and store it in variable `chunkName`, after that any line not matched by any regular expression is added to Map named `chunks` 
with value of `chunkName` as a key.
If line matches with end of chunk expression `chunkName` is set ot zero value. If expressions can match line and `chunkName` variable set to zero value, that line will added to `document` string variable.

<<Reading and processing lines>>=
	for {
		line, err := fileBuf.ReadString('\n')
		if err == io.EOF {
			processLine(line)
			break
		} else if err != nil {
			panic(err)
		}
		var matches = chunkMatcher.FindStringSubmatch(line)
		if matches != nil {
			chunkName = matches[1]
			chunks[chunkName] = ""
		} else if matches = endOfChunkMatcher.FindStringSubmatch(line); matches != nil {
			chunkName = ""
		} else {
			processLine(line)
		}
	}
@

As a result of execution `parseFile` function returns `document` string and `chunks` map. 

<<File parsing definition>>=
func parseFile(fileName string, keepSourceCode bool) (map[string]string, string) {

	<<Open file and buf reader>>

	<<Define regular expressions>>
	
	var document string
	var chunkName string
	var chunks = make(map[string]string)

	<<Proc line closure>>
	<<Reading and processing lines>>

	return chunks, document
}
@

To simplify processing of every line of code defined closure `processLine`. This closure decides where current processing line will go: to the chunk body or documentation.

<<Proc line closure>>=
	var processLine = func(line string) {
		if chunkName != "" && keepSourceCode == false {
			chunks[chunkName] += line
		} else {
			document += line
		}
	}
@


# Expanding chunks

Every chunk body can contain any number of links to another chunks. To build whole program from literate source we need to "expand" every chunk body by replacing links to other chunks by its bodies.
First of all we define data structure for "final" expanded chunks `expandedChunks`. After that we define regular expression, which will match "links" to other chunks.

<<Define expanded chunks and regexp>>=
	var expandedChunks = make(map[string]string)
	chunkMatcher, err := regexp.Compile("<<([^>]+)>>")
	if err != nil {
		panic(err)
	}
@

Expand body closure defined inside `expandChunks` function takes a body as an argument and match it for links to another chunks. After that it takes every linked chunk name and replaces it with
result of recursive self-invocation with linked chunk body.
If there is no linked chunks closure just returns given body. May be I should check if `expandedChunks` already has expanded body for linked chunk to avoid extra work. And definitelly I should 
detect recursion.

<<Define expand body closure>>=
	var expandBody func(b string) string
	expandBody = func(b string) string {
		var newBody = b
		submatches := chunkMatcher.FindAllStringSubmatch(b, -1)
		if submatches != nil {
			for _, matches := range submatches {
				fullChunk, chunkName := matches[0], matches[1]
				if chunks[chunkName] != "" {
					newBody = strings.Replace(newBody, fullChunk, expandBody(chunks[chunkName]), -1)
				}
			}
		}
		return newBody
	}
@

<<Expanding chunks definition>>=
func expandChunks(chunks map[string]string) map[string]string {

	<<Define expanded chunks and regexp>>

	<<Define expand body closure>>

	for name, body := range chunks {
		expandedChunks[name] = expandBody(body)
	}

	return expandedChunks
}
@

# Main program structure

<<*>>=
package main

import (
<<Used packages>>
)

func main() {
	<<Command line parsing>>
	<<Parameters check>>

	chunks, document := parseFile(parsingFile, keepSourceCode)
	chunks = expandChunks(chunks)

	<<Processing command line>>
}

<<File parsing definition>>
<<Expanding chunks definition>>

@





