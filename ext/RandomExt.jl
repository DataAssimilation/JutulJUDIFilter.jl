"This module extends JutulJUDIFilter with functionality from Random."
module RandomExt

using JutulJUDIFilter: JutulJUDIFilter
using Random

"""
    greeting()

Call [`JutulJUDIFilter.greeting`](@ref) with a random name.


# Examples

```jldoctest
julia> @test true;

```

"""
JutulJUDIFilter.greeting() = JutulJUDIFilter.greeting(rand(5))

end
