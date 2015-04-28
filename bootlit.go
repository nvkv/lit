package main

import (
	"regexp"
	"flag"
	"bufio"
	"fmt"
	"os"
	"io"
	"strings"
)

func main() {
	var sourceFile string
	var docFile string
	var parsingFile string
	var defaultChunk string

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage of lit: lit [options] file-to-parse.w\n")
		flag.PrintDefaults()
	}

	flag.StringVar(&defaultChunk, "default-chunk", "*", "Default program chunk")
	flag.StringVar(&sourceFile, "src-out", "", "File to write source code")
	flag.StringVar(&docFile, "doc-out", "", "File to write document")
	flag.Parse()

	if len(flag.Args()) > 0 {
		parsingFile = flag.Arg(0)
	}
	
	if parsingFile == "" || (sourceFile == "" && docFile == "") {
		flag.Usage()
		os.Exit(0)
	}

	chunks, document := parseFile(parsingFile)
	chunks = expandChunks(chunks)

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
}


func parseFile(fileName string) (map[string]string, string) {
	f, err := os.Open(fileName)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	fileBuf := bufio.NewReader(f)

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
	
	var document string
	var chunkName string
	var chunks = make(map[string]string)

	var processLine = func(line string) {
		if chunkName != "" {
			chunks[chunkName] += line
		} else {
			document += line
		}
	}
	
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
	return chunks, document
}


func expandChunks(chunks map[string]string) map[string]string {

	var expandedChunks = make(map[string]string)
	chunkMatcher, err := regexp.Compile("<<([^>]+)>>")
	if err != nil {
		panic(err)
	}

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

	for name, body := range chunks {
		expandedChunks[name] = expandBody(body)
	}

	return expandedChunks
}