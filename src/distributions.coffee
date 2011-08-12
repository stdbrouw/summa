_ = require './helpers'
math = require './math'

# Calculator is a class that allows us to do calculations on a distribution.
# **All calculations that don't return a new distribution are housed here**, whereas those
# that do (transformations) are housed in the Distribution class, which we'll see later.
#
# Why? No particular reason, except for tidiness.
class Calculator
    constructor: (@distribution) ->

    pmf: ->
        return @_pmf if @_pmf?
        @_pmf = new Pmf @distribution

    cdf: ->
        return @_cdf if @_cdf?
        @_cdf = new Cdf @distribution

    mean: ->
        _.sum(@distribution.values)/@distribution.values.length
        
    median: ->
        values = _.sortBy @distribution.values, (x) -> x
        i = Math.round values.length/2
        values[i-1]

    interpolated_median: ->
        if @has_true_median()
            @median()
        else
            lh = math.floor(0.5*@distribution.values.length) - 1
            math.sum(@distribution.values[lh..lh+1]...)/2

    has_true_median: ->
        # any distribution with an odd amount 
        # of observations has a true median
        @distribution.values.length % 2 is 1
    
    modes: ->
        values = _.items @pmf().values
        values = _.sortBy values, (x) -> x[1]
        [most_frequent, highest_frequency] = _.last(values)

        modes = values.filter (value) -> value[1] == highest_frequency
        modes.map (mode) -> parseFloat mode[0]

    is_multimodal: ->
        @modes().length > 1
    
    mean_deviation: (mu, power = 1) ->
        mu ?= @mean()
        deviations = (Math.pow(x - mu,  power) for x in @distribution.values)
        new Distribution(deviations, false).calculate.mean()

    variance: (mu) ->
        @mean_deviation mu, 2

    skewness: (mu) ->
        m2 = @mean_deviation mu, 2
        m3 = @mean_deviation mu, 3

        m3 / Math.pow(m2, 3/2)
        
    pearson_skewness: (mu) ->
        mu ?= @mean()
        median = @median()
        dev = @stddev()
        
        3*(mu-median)/dev
    
    stddev: (k = 1) ->
        k * Math.sqrt @variance.apply @, arguments

    central_moment: (k = 1) ->
        'todo'

    kurtosis: ->
        'todo'
    
    range: ->
        [Math.min.apply(null, @distribution.values), Math.max.apply(null, @distribution.values)]

    approximate_interquartile_range: ->
        values = @distribution.values
        # we don't use @rank percentile: 25 because ordinal percentiles
        # are always rounded upwards, whereas for our approximation
        # we want the closest match, up or down
        left = math.round(0.25*values.length)
        right = values.length - left
        left_percentile = left/values.length
        right_percentile = right/values.length

        range = {}
        range[left_percentile] = @distribution.values[left-1]
        range[right_percentile] = @distribution.values[right-1]

        range

    interpolated_interquartile_range: ->
        values = @distribution.values        
        left = @index(percentile: 25)
        right = values.length - left

        lh = (@distribution.values[left-1] + @distribution.values[left]) / 2
        rh = (@distribution.values[right-1] + @distribution.values[right]) / 2

        [lh, rh]

    # The interquartile range is a measure of spread.
    # It cuts off the lowest and highest 25% of data.
    interquartile_range: ->    
        lh = @index(percentile: 25)
        rh = @index(percentile: 75)
        [@distribution.values[lh], @distribution.values[rh]]

    rank: (options) ->
        if options.value?
            _.bisect_left(@distribution.values, options.value) + 1
        else if options.percentile?
            # although the + 1/2 is really arbitrary, this is a
            # common textbook definition according to Wikipedia
            rank = options.percentile/100 * @distribution.values.length + 1/2
            # ranks are ordinal
            math.round rank
        else
            throw new Error "We can only rank given a percentile or a value"

    # Statistics traditionally talks about ranks, which go from 1 to n, 
    # but us computer programmers know better, and index lists from 0 
    # onwards. The index is the rank minus one. 
    index: (options) ->
        @rank(options) - 1

    percentile: (value) ->
        rank = @rank value: value
        math.ceil rank/@distribution.values.length * 100
    
    count: (n) ->
        if n
            occurrences = @distribution.values.filter (value) -> value is n
            occurrences.length
        else
            @distribution.values.length

# A lot of calculations make sense on both the entire dataset and a smaller 
# part of it. For example, you can count the frequency of a certain value, but 
# you can also count all data points at a time. But other calculations really
# only work for a specific range or data point, and here's a list of those.
Calculator::local = [
    'index'
    'rank'
    'percentile'
    ]

class Histogram
    constructor: (@distribution) ->
        @values = {}
        
        for x in @distribution.values
            @values[x] = (@values[x] or 0) + 1

    # creates a normalized histogram, also known 
    # as a probability mass function
    normalize: ->
        pmf = _.clone @
        size = pmf.distribution.values.length

        for key, count of pmf.values
            pmf.values[key] = count/size

        pmf

    # creates a histogram with cumulated frequencies or probabilities, 
    # also known as a cumulative distribution function
    cumulate: ->
        cdf = _.clone @
        tuples = _.items @values
        sorted_tuples = _.sortBy tuples, (a) -> parseFloat a[0] 

        running_tally = 0
        for tuple in sorted_tuples
            [key, value] = tuple
            cdf.values[key] = running_tally + value
            running_tally = cdf.values[key]
    
        cdf

    # Puts the distribution into bins.
    # The keys are the center value, so e.g. a bin called 
    # 40 with an interval of 10 comprises values between 35 
    # and 44
    bin: (interval) ->
        values = _.groupBy @distribution.values, (value) -> Math.round(value/interval)*interval
        new Pmf values

Histogram::empty = ->
    new Histogram {values: []}

# shortcuts

Pmf = (distribution) -> 
    new Histogram(distribution).normalize()    

Cdf = (distribution) ->
    new Histogram(distribution).cumulate()

class Distribution
    constructor: (@values, @precalculations) ->
        # When creating a new distribution, people can specifically ask
        # **which summary statistics they wish to be calculated**.
        # But if they don't ask for anything in particular, we 
        # calculate every summary value we can think of -- the computing
        # time is negligable anyway, except for really big data sets.
        @calculate = new Calculator @

        if not @precalculations?
            fns = _.functions Calculator.prototype
            @precalculations = _.reject fns, (fn) -> _.contains(Calculator::local, fn)
        
        for calculation in @precalculations
            @[calculation] = @calculate[calculation]()

    normalize: (range = {}) ->
        options = {top: 1}
        range = _.extend(range, options)
    
        if range.bottom
            min = Math.min.apply null, @values
            ratio = range.bottom/min
        else if range.top
            max = Math.max.apply null, @values
            ratio = range.top/max

        values = @values.map (value) -> value*ratio        
        new Distribution values, @precalculations

    round: (digits = 0) ->
        values = @values.map (value) -> math.round value, digits
        
        new Distribution values, @precalculations

    trim: (options) ->
        if options.percentage
            'todo'
        else if options.lt or options.gt
            'todo'
        else if options.stddev
            'todo'

    # note that absolute difference and relative difference
    # are not counterpoints to each other, they're different
    # calculations altogether
    difference: (distribution, options) ->
        unless @values.length == distribution.values.length
            throw Error "Can only compare two like-sized distributions"

        sets = _.zip(@values, distribution.values)
        
        # relative risk
        if options?.relative == yes
            sets.map (value) -> value[1] / value[0]
        # absolute difference
        else if options?.absolute == yes
            sets.map (value) -> Math.abs value[1] - value[0]
        # regular difference
        else
            sets.map (value) -> value[1] - value[0]

    partition: (n) ->
        _.partition(@values, n).map (partition) -> new Distribution partition, @precalculations

    sample: (n, options) ->
        s = random.sample @values, n, options.replacement
        new Distribution s, @precalculations

    # Resampling differs from sampling in that resampling generates random
    # values that fit the distribution instead of picking random values from
    # the existing data.
    resample: (n, options) ->
        # create a CDF

exports.Calculator = Calculator
exports.Distribution = Distribution
exports.Histogram = Histogram
