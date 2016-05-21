using ArgParse

str{S<:AbstractString}(s::SubString{S}) = convert(S, s)

type Detokenizer
    wikipedia  ::AbstractString
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
        new(wikipedia, not_word, move_left,
            move_right, long_dep, cache, exceptional)
    end
end

function Detokenizer(rulefile, wikifile)
    characters = ""
    cache  = Dict{AbstractString,Int}()
    right = AbstractString[]
    dep = Tuple{ASCIIString,ASCIIString}[]
    info("LOADING RULE FILE")
    for line in open(readlines, rulefile)
        ( length(line) == 0 || !(line[1] in "CLRD") ) && continue
        line = split(chomp(line), "\t")
        rule = line[1]
        if rule == "C"
            characters *= join(line[2:end], "")
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
    not_word(word) = ismatch(Regex("[^($characters)]"), word) || ismatch(r"https?://.+", word)
    info("TO LEFT RULES:", join(keys(cache), ", "))
    info("TO RIGHT RULES:", join(right, ", "))
    info("LONG DEPENDENCIES:", join(dep, ", "))
    info("CHARACTERS:", characters)

    info("LOADING WIKIPEDIA")
    wikipedia = readall(wikifile)
    info("LOWERCASING..")
    for char in wikipedia
        char = lowercase(char)
    end
    info("DONE")
    Detokenizer(wikipedia, not_word, move_left, move_right, dep, cache)
end

# wikipediaを使って縮約するか調べる候補
# not_word = r"[^a-zA-Z0-9]"
# url = r"https?://.+"
# not_alphabetical(word) = ismatch(not_word, word) || ismatch(url, word)
# not_alphabetical(words...) = any(not_alphabetical, words)

# あまりwikipediaをlookupしすぎないように
# cache = [k => typemax(Int) for k in ["n\'t", "\'s", "\'d", "\'ve", "\'ll", "\'re", "\'m"]] |> Dict

function searchall(s, t, overlap::Bool=false)
    idxfcn = overlap ? first : last
    r = search(s, t)
    n = 0
    while last(r) > 0
        n += 1
        r = search(s, t, idxfcn(r) + 1)
    end
    n
end
function wiki_count(target::AbstractString, de::Detokenizer)
    res = get!(de.cache, lowercase(target), searchall(de.wikipedia, target))
    info(lowercase(target), " => ", res)
    res
end

function detokenized_sent(sent, to_left)
    to_left[1] = true
    join([to_left[i] ? word : " "*word for (i, word) in enumerate(sent)], "")
end

# クオート等の長距離依存を伴うものを調べる
# capable of handling nestedness
function long_dependency(sent, from, to)
    res = Array{Int}[]
    from in sent && to in sent || return res
    tmp = Array{Int}[]
    for (i, word) in enumerate(sent)
        if word == from
            push!(tmp, [i])
        elseif word == to
            @assert length(tmp[end]) == 1
            push!(tmp[end], i)
            push!(res, pop!(tmp))
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

function readconll(filename)
    info("LOADING SENTENCES")
    sents = Array{ASCIIString}[[]]
    skip = 0:0
    for line in open(readlines, filename, "r")
        line = chomp(line)
        if length(line) == 0
            push!(sents, ASCIIString[])
            continue
        end
        line = split(line, "\t")
        num = line[1]
        # need to take into account morphologically rich
        if contains(num, "-")
            skip = range(num)
        elseif parse(Int, num) in skip
            continue
        else
            push!(sents[end], str(line[2]))
        end
    end
    info("DONE")
    sents
end

function detokenize{S<:AbstractString}(sent::Array{S}, de::Detokenizer)
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
    # bigram単位で縮約するか調べる
    for i in 1:n_words-1
        word1, word2 = sent[i:i+1]
        if !(word1 in de.exceptional) && !to_left[i+1] && (de.not_word(word1) || de.not_word(word2))
            if wiki_count(word1*word2, de) > wiki_count(word1*" "*word2, de)
                to_left[i+1] = true
            end
        end
    end
    res = detokenized_sent(sent, to_left)
    println(res)
    info("TO  : ", res, "\n")
end

function detokenize{S<:AbstractString}(sents::Array{Array{S}}, de::Detokenizer)
    for sent in sents
        detokenize(sent, de)
    end
end

function main()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--conll", "-c"
            help = "conll file to detokenize"
            required = true
        "--rules", "-r"
            help = "rule file"
            required = true
        "--wiki", "-w"
            help = "wikipedia dump"
            required = true
    end
    args  = parse_args(ARGS, s)
    sents = readconll(args["conll"])
    de    = Detokenizer(args["rules"], args["wiki"])
    detokenize(sents, de)
end

main()
