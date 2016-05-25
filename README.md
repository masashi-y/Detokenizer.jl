# Detokenizer.jl
Program to undo tokenization of corpus data.

    In : Al - Zaman : American forces killed Shaikh Abdullah al - Ani , the preacher at the mosque in the town of Qaim , near the Syrian border .
    Out: Al-Zaman: American forces killed Shaikh Abdullah al-Ani, the preacher at the mosque in the town of Qaim, near the Syrian border.

Some detokenization is done by a rule-based manner,
while Ambiguous cases(Al-Zaman here) are treated by choosing more frequent 2,3-gram patterns.

    usage: detokenize.jl [-t TEXT [TEXT...]] [-c CONLL [CONLL...]]
                         -r RULES -w WIKI [-h]
    
    optional arguments:
      -t, --text TEXT [TEXT...]
                            one-sent-per-line text file to detokenize
      -c, --conll CONLL [CONLL...]
                            conll file to detokenize
      -r, --rules RULES     rule file
      -w, --wiki WIKI       wikipedia dump
      -h, --help            show this help message and exit

# Requirements
* Julia 0.4 or later
* DistributedArrays (https://github.com/JuliaParallel/DistributedArrays.jl)

# Usage
1. Download Wikipedia dump e.g. \*\*-pages-articles.xml.bz2. (https://dumps.wikimedia.org/)
2. Extract plain text from the dump.
    reccomended: https://github.com/attardi/wikiextractor
3. Write a rule file which defines the common character set of the language.
   (see rules/eng.rule for the detail.)
4. Prepare a file with sentences to detokenize. (CoNLL format file or file with one sent per line)
5. Run detokenize.jl.
   julia -p 20 detokenize.jl -t one-sent-per-line file -c {test,dev,train}.conll -r rule\_file -w wiki\_dump
   The program generates \*.detok file which is the result of detokenization.

* For languages with extended latin alphabet rules/latin\_alphabet.rule can be used.
* Using julia option -p is recommended so that detokenizer runs on multi cores
* Passing the files to detokenize all at once (e.g. {test,dev,train}.conll) as this helps detokenization complete faster.
  (Loading wikipedia dump takes much time and the wikipedia lookup cache prevents too many lookup operations.)
