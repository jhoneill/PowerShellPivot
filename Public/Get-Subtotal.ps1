function Get-Subtotal  {
    <#
      .SYNOPSIS
        Adds subtotals to data
      .DESCRIPTION
        Combines Measure-Object and Group object - groups on one or more properties,
        and calculates different measures across properties in the group
        It does NOT support custom properties (so use Select-object and pipe into
        Get-Subtotal), and you if you ask for min, max and average, and Width and Height
        you will get six items, and if you want width_min, width_max, height_average, again
        Select-Object is there for the task.
      .EXAMPLE
        Get-ChildItem  | Get-Subtotal Length -Allstats  -Group  Extension | ft
        Produces a table of count, average, sum,  min, max and standard deviation for file length grouped by file extension.
      .EXAMPLE
        Get-ChildItem  | Select-object *, @{n='Month';e={$_.LastWriteTime.toString("yyyy_MM")}} | Get-Subtotal -GroupByName Extension, month
        Adds a "Month" column in the form "2022-02" to files, groups by month and file extension and returns a count for each group
      .EXAMPLE
         Get-ChildItem | Get-Subtotal -GroupByName Extension -ValueName LastWriteTime, CreationTime -Maximum -Minimum | ft
         Produces a table by file extension of min and max dates for file creation and last write
    #>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        #The property name(s) to group on.
        [Parameter(Position=0)]
        $GroupByName,
        #The property name(s) to aggregate - if none is specified items are counted
        [Parameter(Position=1)]
        $ValueName,
        #The data to subtotal 'Character', 'Line', 'Word' use Measure-object, the rest use code that extends the Group object
        # 'Average', 'CountValues',  'Sum', 'Max', 'Min', 'Std' and  'Var' don't use any addition code, but use [MathNet.Numerics.Statistics] is needed for
        # 'Entropy', 'Mean', 'GeometricMean', 'HarmonicMean',  'Median' 'RootMeanSquare', 'Quantile', 'LowerQuartile', 'UpperQuartile',
        # 'StandardDeviation', 'PopulationStandardDeviation',  'Variance', and 'PopulationVariance'
        [Parameter(Position=2)]
        [ValidateSet('Average', 'CountValues',  'Sum', 'Max', 'Min', 'Std', 'Var',
                     'Entropy', 'Mean', 'GeometricMean', 'HarmonicMean',  'Median',
                     'RootMeanSquare', 'Quantile', 'LowerQuartile', 'UpperQuartile',
                     'StandardDeviation', 'PopulationStandardDeviation',  'Variance', 'PopulationVariance',
                     'AllStats',  'Character', 'Line', 'Word')]
        [String[]]$AggregateFunction = @('Sum'),

        [Parameter(ValueFromPipeline=$true)]
        $InputObject,

        [Alias('NoPrefix','NoSuffix')]
        [switch]$SimpleName,

        #The swtiches for "Count", "Average", "Maximum", "Minimum", "StandardDeviation", "Sum", "Character", "Line" and "Word" make calling from convertToCrossTab easier
        #-Sum is equivalent to adding Sum to $AggregateFunction
        [switch]$Sum,
        #Equivalent to adding countValues (not count) to -AggregateFunction
        [switch]$Count,
        #Equivalent to adding max (not 'Maximum') to -AggregateFunction
        [switch]$Maximum,
        #Equivalent to adding min (not 'Minimum') to -AggregateFunction
        [switch]$Minimum,
        #Equivalent to adding Average to AggregateFunction (average doesn't need [MathNet.Numerics.Statistics] , mean does )
        [switch]$Average,
        #Equivalent to adding Std (not StandardDeviation) to $AggregateFunction (std doesn't need [MathNet.Numerics.Statistics] , StandardDeviation does )
        [Alias('Std')]
        [switch]$StandardDeviation,
        #Equivalent to adding var (not variance) to $AggregateFunction  (var doesn't need [MathNet.Numerics.Statistics] , variance does )
        [switch]$Var,
        #Equivalent to adding AllStats to -AggregateFunction -selects "Min", "Max", "Average", "STD", "Sum" and, "Count"
        [switch]$AllStats,
         #Equivalent to adding Character to -AggregateFunction - uses Measure-Object to count Characters
        [switch]$Character,
         #Equivalent to adding word to -AggregateFunction - uses Measure-Object to count Lines
        [switch]$Line,
         #Equivalent to adding word to -AggregateFunction - uses Measure-Object to count words
        [switch]$Word,
        # Ignores whitespace when measuring Chars words or lines
        [switch]$IgnoreWhiteSpace
    )
    begin   {
        #region Allow switches for common options - if nothing was passed as a switch or as -AggregateFunction the default value will take over, but if a swtch was passed removed the default
         if ((-not $PSBoundParameters["AggregateFunction"]) -and ($Minimum -or $Maximum -or $CountValues -or $AllStats -or $Average -or $StandardDeviation -or $sum -or $Character -or $line -or $word )) {
             $AggregateFunction = @()
        }
        if ( $Count                    -and $AggregateFunction -notcontains "CountValues" ) {$AggregateFunction += "CountValues"}
        if ( $Minimum                  -and $AggregateFunction -notcontains "Min"         ) {$AggregateFunction += "Min"}
        if ( $Maximum                  -and $AggregateFunction -notcontains "Max"         ) {$AggregateFunction += "Max"}
        if ( $StandardDeviation        -and $AggregateFunction -notcontains "Std"         ) {$AggregateFunction += "Std"}
        foreach ($p in @("AllStats", "Average", "Var", "Sum", "Character", "Line", "Word")) {
            if ($PSBoundParameters[$p] -and $AggregateFunction -notcontains  $P)             {$AggregateFunction += $p}
        }
        #endregion

        #region divide parameters into those done using measure and those done with type extensions to the group object.
        $measureParams = $AggregateFunction.where({$_ -in    ("Line", "Character", "Word") })
        if     ($IgnoreWhiteSpace -and -not $measureParams) {$measureParams  = @('Character', 'IgnoreWhiteSpace' ) }
        elseif ($IgnoreWhiteSpace )                         {$measureParams +=                'IgnoreWhiteSpace'   }
        if ($SimpleName -and $measureParams) {
            Write-Warning "Simple name option is ignored for text counts."
        }

        $groupParams = $AggregateFunction.where({$_ -Notin ("Line", "Character", "Word", "AllStats") })
        if ($AggregateFunction -contains 'AllStats') {
            if ($groupParams) {Write-Warning 'AllStats overrides other Aggregate functions'}
            $groupParams = "Min", "Max", "Average", "STD", "Sum", "Count"
        }
        if ($measureParams -and $groupParams ) {
            Write-Warning "Can't use mathematical and textual functions, matematical ones will be ignroed"
        }
        if ($SimpleName    -and $groupParams.Count -gt 1 -and $GroupByName.count -gt 1 ) {
            Write-Warning "Simple name option is ignored when there are multiple aggregations."
        }
        #endregion

        $data   = @()
    }
    process {
        $data  += $inputObject
    }
    end {
        $data | Group-Object -Property $GroupByName | ForEach-Object {
            $newobj = [Ordered]@{}
            #For whatever we grouped on, get that value/those values from the first row of each group. Then total the properties we're interested in
            foreach ($g in $GroupByName) {$newobj[$g]      = $_.Group[0].$g }
            if (-not       $ValueName)   {$newobj['Count'] = $_.Group.Count}
            foreach ($v in $ValueName)   {
                #Some objects may not have all the properties e.g. Dir | measure length
                if     ($measureParams)  {
                    $totals =  $_.Group | Measure-object -Property $v @measureParams -ErrorAction SilentlyContinue
                    foreach ($agFn  in $measureParams.Keys.where({$_  -ne 'IgnoreWhiteSpace'}))  {
                        $newObj[($v + "_" + $agfn + "s")] = $totals."$agFn`s"
                    }
                }
                elseif ($groupParams)    {
                    if     ($groupParams.Count -eq 1 -and $SimpleName) {
                            $agFn       = $groupParams[0];   $newObj[$v]                 = $_.$agFn($v)
                    }
                    elseif ($GroupByName.count -eq 1 -and $SimpleName) {
                        foreach ($agFn in $groupParams)  {   $newObj[$agfn]              = $_.$agFn($v)}
                    }
                    else {
                        foreach ($agFn in $groupParams)  {  $newObj[($agfn + "_" + $v )] = $_.$agFn($v)}
                    }
                }
            }
            [pscustomobject]$newobj
        }
    }
}