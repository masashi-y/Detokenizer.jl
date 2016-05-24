# Detokenizer.jl
program to undo tokenization of corpus data

    usage: detokenize.jl [-t TEXT [TEXT...]] [-c CONLL [CONLL...]]
                         -r RULES -w WIKI [-h]
    
    optional arguments:
      -t, --text TEXT [TEXT...]
                            one-sent-per line text file to detokenize
      -c, --conll CONLL [CONLL...]
                            conll file to detokenize
      -r, --rules RULES     rule file
      -w, --wiki WIKI       wikipedia dump
      -h, --help            show this help message and exit

# Requirements
* Julia 0.4 or later
* DistributedArrays (https://github.com/JuliaParallel/DistributedArrays.jl)
