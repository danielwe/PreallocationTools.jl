module PreallocationTools

using ForwardDiff, ArrayInterface, LabelledArrays, Adapt

struct DiffCache{T<:AbstractArray, S<:AbstractArray}
    du::T
    dual_du::S
end

function DiffCache(u::AbstractArray{T}, siz, chunk_sizes) where {T}
    x = adapt(ArrayInterface.parameterless_type(u), zeros(T, prod(chunk_sizes .+ 1)*prod(siz)))
    DiffCache(u, x)
end

"""

`dualcache(u::AbstractArray, N::Int = ForwardDiff.pickchunksize(length(u)); levels::Int = 1)`
`dualcache(u::AbstractArray; N::AbstractArray{<:Int})`

Builds a `DualCache` object that stores both a version of the cache for `u`
and for the `Dual` version of `u`, allowing use of pre-cached vectors with
forward-mode automatic differentiation. Supports nested AD via keyword `levels`
or specifying an array of chunk_sizes.

"""
dualcache(u::AbstractArray, N::Int=ForwardDiff.pickchunksize(length(u)); levels::Int = 1) = DiffCache(u, size(u), N*ones(Int, levels))
dualcache(u::AbstractArray, N::AbstractArray{<:Int}) = DiffCache(u, size(u), N)
dualcache(u::AbstractArray, ::Type{Val{N}}; levels::Int = 1) where N = dualcache(u,N;levels)
dualcache(u::AbstractArray, ::Val{N}; levels::Int = 1) where N = dualcache(u,N;levels)

"""

`get_tmp(dc::DiffCache, u)`

Returns the `Dual` or normal cache array stored in `dc` based on the type of `u`.

"""
function get_tmp(dc::DiffCache, u::T) where T<:ForwardDiff.Dual
    nelem = div(sizeof(T), sizeof(eltype(dc.dual_du)))*length(dc.du)
    if nelem > length(dc.dual_du)
        enlargedualcache!(dc, nelem)
    end
    ArrayInterface.restructure(dc.du, reinterpret(T, view(dc.dual_du, 1:nelem)))
end

function get_tmp(dc::DiffCache, u::AbstractArray{T}) where T<:ForwardDiff.Dual
    nelem = div(sizeof(T), sizeof(eltype(dc.dual_du)))*length(dc.du)
    if nelem > length(dc.dual_du)
        enlargedualcache!(dc, nelem)
    end
    ArrayInterface.restructure(dc.du, reinterpret(T, view(dc.dual_du, 1:nelem)))
end

function get_tmp(dc::DiffCache, u::LabelledArrays.LArray{T,N,D,Syms}) where {T,N,D,Syms}
    nelem = div(sizeof(T), sizeof(eltype(dc.dual_du)))*length(dc.du)
    if nelem > length(dc.dual_du)
        enlargedualcache!(dc, nelem)
    end
    _x = ArrayInterface.restructure(dc.du, reinterpret(T, view(dc.dual_du, 1:nelem)))
    LabelledArrays.LArray{T,N,D,Syms}(_x)
end

get_tmp(dc::DiffCache, u::Number) = dc.du
get_tmp(dc::DiffCache, u::AbstractArray) = dc.du

function enlargedualcache!(dc, nelem) #warning comes only once per dualcache.
    chunksize = div(nelem, length(dc.du)) - 1
    @warn "The supplied dualcache was too small and was enlarged. This incurrs allocations
    on the first call to get_tmp. If few calls to get_tmp occur and optimal performance is essential,
    consider changing 'N'/chunk size of this dualcache to $chunksize."
    resize!(dc.dual_du, nelem)
end


"""
    b = LazyBufferCache(f=identity)

A lazily allocated buffer object.  Given a vector `u`, `b[u]` returns a `Vector` of the
same element type and length `f(length(u))` (defaulting to the same length), which is
allocated as needed and then cached within `b` for subsequent usage.

"""
struct LazyBufferCache{F<:Function}
    bufs::Dict # a dictionary mapping types to buffers
    lengthmap::F
    LazyBufferCache(f::F=identity) where {F<:Function} = new{F}(Dict()) # start with empty dict
end

# override the [] method
function Base.getindex(b::LazyBufferCache, u::AbstractArray{T}) where {T}
    n = b.lengthmap(size(u)) # required buffer length
    buf = get!(b.bufs, T) do
        similar(u, T, n) # buffer to allocate if it was not found in b.bufs
    end::typeof(u) # declare type since b.bufs dictionary is untyped
    # Doesn't work well with matrices, needs more thought!
    #return resize!(buf, n) # resize the buffer if needed, e.g. if problem was resized
end

export dualcache, get_tmp, LazyBufferCache

end
