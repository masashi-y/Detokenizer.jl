using ArgParse
@everywhere using DistributedArrays

str{S<:AbstractString}(s::SubString{S}) = convert(S, s)
num_norm(word) = replace(word, r"\d+", "0")
ex_norm(word)  = replace(word, r"[!?]+", "!")

const SEGLENGTH = 100000
function segment_read(filename)
    res = []
    i = 0; curlen = 0; tmp = ""
    file = open(filename)
    line = readline(file)
    while !eof(file)
        print("now:", i+=1, "\r")
        tmp *= line |> lowercase |> num_norm |> ex_norm
        curlen += length(line)
        if curlen > SEGLENGTH
            push!(res, tmp)
            tmp = ""; curlen = 0
        end
        line = readline(file)
    end
    res
end

@everywhere type Detokenizer
    wikipedia  #::AbstractString
    not_word   ::Function
    move_left  ::Function
    move_right ::Function
    long_dep ::Array{Tuple{AbstractString,AbstractString}}
    cache :: Dict{AbstractString,Int}
    exceptional ::Array{AbstractString}
    function Detokenizer(wikipedia,
                         not_word,
                         move_left,
                         move_right,
                        long_dep,
                        cache)
        exceptional = collect(keys(cache))
        for (from, to) in long_dep
            push!(exceptional, from)
            push!(exceptional, to)
        end
        new(wikipedia, not_word, move_left,
            move_right, long_dep, cache, exceptional)
    end
end

function Detokenizer(rulefile, wikifile)
    characters = ""
    cache = Dict{AbstractString,Int}()
    right = AbstractString[]
    dep = Tuple{UTF8String,UTF8String}[]
    info("LOADING RULE FILE")
    for line in open(readlines, rulefile)
        ( length(line) == 0 || !(line[1] in "CLRD") ) && continue
        line = split(chomp(line), "\t")
        rule = line[1]
        if rule == "C"
            characters *= join(line[2:end])
        elseif rule == "L"
            for word in line[2:end]
                cache[word] = typemax(Int)
            end
        elseif rule == "R"
            append!(right, line[2:end])
        elseif rule == "D"
            if length(line[2:end]) == 2
                push!(dep, (str(line[2]),str(line[3])))
            elseif length(line[2:end]) == 1
                push!(dep, (str(line[2]),str(line[2])))
            end
        end
    end
    move_left(word)  = word in keys(cache)
    move_right(word) = word in right
    not_word(word) = ismatch(Regex("[^($characters)]"), word) #|| !ismatch(r"https?://.+", word)
    info("TO LEFT RULES:", join(keys(cache), ", "))
    info("TO RIGHT RULES:", join(right, ", "))
    info("LONG DEPENDENCIES:", join(["($from, $to)" for (from, to) in dep], ", "))
    info("CHARACTERS:", characters)

    info("LOADING WIKIPEDIA")
    wikipedia = distribute(segment_read(wikifile))
    info("DONE")
    Detokenizer(wikipedia, not_word, move_left, move_right, dep, cache)
end

@everywhere function searchall(s, t, overlap::Bool=false)
    idxfcn = overlap ? first : last
    r = search(s, t)
    n = 0
    while last(r) > 0
        n += 1
        r = search(s, t, idxfcn(r) + 1)
    end
    n
end
@everywhere function wiki_count(de::Detokenizer, target)
    target = " "*target*" " |> lowercase |> num_norm |> ex_norm
    if target in keys(de.cache)
        res = de.cache[target]
        info(target, " => ", res)
    else
        res = sum(map(x->searchall(x, target), de.wikipedia))
        de.cache[target] = res
        info("**No.$(length(de.cache)) ", target, " => ", res)
    end
    res
end

function detokenized_sent(sent, to_left)
    to_left[1] = true
    join([to_left[i] ? word : " "*word for (i, word) in enumerate(sent)])
end

global idx = 0
function detokenized_sent_conll(sent, to_left)
    to_left[1] = true
    function to_line(word)
        idx += 1
        join([idx, word], "\t") * "\n"
    end
    res = map(enumerate(sent)) do (i, word)
        if to_left[i]
            line = to_line(" ") # line for space
        else
            line = ""
        end
        line *= to_line(word)
    end |> join
    res *= to_line("LF")
    res
end

# クオート等の長距離依存を伴うものを調べる
function long_dependency(sent, from, to)
    res = Array{Int}[]
    from in sent && to in sent || return res
    tmp = Array{Int}[]
    for (i, word) in enumerate(sent)
        if length(tmp) > 0 && length(tmp[end]) == 1 && word == to
            push!(tmp[end], i)
            push!(res, pop!(tmp))
        elseif word == from
            push!(tmp, [i])
        end
    end
    res
end

# convert "2-3" to 2:3 range object
function range(str::AbstractString)
    str = split(str, "-")
    @assert length(str) == 2
    from, to = map(x->parse(Int, x), str)
    from:to
end

function readraw(filename)
    info("LOADING SENTENCES")
    map(chomp, open(readlines, filename, "r"))
end

function readconll(filename)
    info("LOADING SENTENCES")
    sents = Array{UTF8String}[[]]
    skip = 0:0
    for line in open(readlines, filename, "r")
        line = chomp(line)
        if length(line) == 0
            push!(sents, UTF8String[])
            continue
        elseif !isdigit(line[1])
            continue
        end
        line = split(line, "\t")
        num = line[1]
        # need to take into account morphologically rich
        if contains(num, "-")
            skip = range(num)
            push!(sents[end], str(line[2]))
        elseif parse(Int, num) in skip
            continue
        else
            push!(sents[end], str(line[2]))
        end
    end
    info("DONE")
    sents
end

function detokenize{S<:AbstractString}(sent::Array{S}, de::Detokenizer, out)
    length(sent) == 0 && return
    info("FROM: ", join(sent, " "))
    to_left = [false for w in sent]
    n_words = length(sent)
    for (from, to) in de.long_dep
        for (dep1, dep2) in long_dependency(sent, from, to)
            to_left[dep1+1], to_left[dep2] = true, true
        end
    end
    # unigram単位で縮約するか調べる
    for i in 1:n_words
        word = sent[i]
        de.move_left(word) && (to_left[i] = true)
        i < n_words-1 && de.move_right(word) && (to_left[i+1] = true)
    end
    # trigram単位で縮約するか調べる
    for i in 1:n_words-2
        word1, word2, word3 = sent[i:i+2]
        if !(word1 in de.exceptional || word2 in de.exceptional || word3 in de.exceptional) &&
                !to_left[i+1] && !to_left[i+2] && any(de.not_word, [word1, word2, word3]) &&
                    wiki_count(de, word1*word2*word3) > wiki_count(de, word1*" "*word2*" "*word3)
            to_left[i+1], to_left[i+2] = true, true
        end
    end
    # bigram単位で縮約するか調べる
    for i in 1:n_words-1
        word1, word2 = sent[i:i+1]
        if !(word1 in de.exceptional || word2 in de.exceptional) &&
                !to_left[i+1] && any(de.not_word, [word1, word2]) &&
                    wiki_count(de, word1*word2) > wiki_count(de, word1*" "*word2)
            to_left[i+1] = true
        end
    end
    res = detokenized_sent_conll(sent, to_left)
    println(out, res)
    info("TO  : ", detokenized_sent(sent, to_left), "\n")
end

function detokenize{S<:AbstractString}(sents::Array{Array{S}}, de::Detokenizer, doc)
    out = open(doc*".detok", "w")
    info("INPUT: ", doc)
    info("OUPUT: ", doc*".detok")
    for sent in sents
        detokenize(sent, de, out)
    end
    close(out)
end

function main()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--text", "-t"
            help = "one-sent-per line text file to detokenize"
            nargs = '+'
        "--conll", "-c"
            help = "conll file to detokenize"
            nargs = '+'
        "--rules", "-r"
            help = "rule file"
            required = true
        "--wiki", "-w"
            help = "wikipedia dump"
            required = true
    end
    args  = parse_args(ARGS, s)
    @assert length(args["text"]) > 0 || length(args["conll"]) > 0
    de    = Detokenizer(args["rules"], args["wiki"])
    for doc in args["text"]
        sents = readraw(doc)
        @time detokenize(sents, de, doc)
    end
    for doc in args["conll"]
        sents = readconll(doc)
        @time detokenize(sents, de, doc)
    end
end

@time main()
