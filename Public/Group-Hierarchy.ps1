function Group-Hierarchy {
    param   (
        [Parameter(position=0)]
        [System.Collections.ArrayList]$Property,

        [Parameter(position=1,Mandatory=$true,ValueFromPipeline=$true)]
        [System.Collections.ArrayList]$InputObject
    )
    begin   {$data =  @()}
    process {$data += $InputObject}
    end     {
        if ($Property.count -eq 0) {$data }
        else {
            $CurrentProperty = $Property[0]
            $p = $Property.Clone()
            $p.RemoveAt(0)
            $hash = [ordered]@{}
            $data | Group-Object -Property $CurrentProperty | ForEach-Object {
                if (-not $_.name) {$Name = "None"} else {$name = $_.Name}
                $hash[$Name] = Group-Hierarchy -Property $P -InputObject $_.Group
            }
            $hash
        }
    }
}
