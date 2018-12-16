mutable struct TRSinfo
	is_hard::Bool  # Flag indicating if we are in the hard case
	niter::Int # Number of iterations in eigs
	nmul::Int  # Number of multiplication with P in eigs
	λ::Vector  # Lagrange Multiplier(s)

	function TRSinfo(is_hard::Bool, niter::Int, nmul::Int, λ::Vector)
		new(is_hard, niter, nmul, λ)
	end
end

function trs_boundary(P, q::AbstractVector{T}, r::T, C::AbstractArray; kwargs...) where {T}
	check_inputs(P, q, r)
	return trs_boundary((nev; kw...) -> gen_eigenproblem(P, q, r, C, nev; kw...),
		   (λ, V; kw...) -> pop_solution!(P, q, r, C, V, λ; kw...); kwargs...)
end

function trs_boundary(P, q::AbstractVector{T}, r::T; kwargs...) where {T}
	check_inputs(P, q, r)
	return trs_boundary((nev; kw...) -> eigenproblem(P, q, r, nev; kw...),
		   (λ, V; kw...) -> pop_solution!(P, q, r, I, V, λ; kw...); kwargs...)
end

function trs_boundary(solve_eigenproblem::Function, pop_solution!::Function;
	compute_local=false, tol_hard=1e-4, kwargs...)

	if compute_local
		nev=2  # We will need the two rightmost eigenvalues
	else
		nev=1  # We will only need the rightmost eigenvalue
	end

	λ, V, niter, nmult = solve_eigenproblem(nev; kwargs...)
	x1, x2, λ1 = pop_solution!(λ, V; tol_hard=tol_hard) # Pop global minimizer(s).
	if !compute_local
		return x1, TRSinfo(isempty(x2), niter, nmult, [λ1])
	else
		if isempty(x2) # i.e. we are not in the hard-case
			hard_case = false
			x2, _, λ2 = pop_solution!(λ, V) # Pop local-no-global minimizer.
		else
			λ2 = λ1
			hard_case = true
		end
		return x1, x2, TRSinfo(hard_case, niter, nmult, [λ1; λ2])
	end
end

function check_inputs(P, q::AbstractVector{T}, r::T) where {T}
	@assert(issymmetric(P), "The cost matrix must be symmetric.")
	@assert(eltype(P) == T, "Inconsistent element types.")
	@assert(size(P, 1) == size(P, 2) == length(q), "Inconsistent matrix dimensions.")
end

function pop_solution!(P, q::AbstractVector{T}, r::T, C, V::Matrix{Complex{T}}, λ::Vector{Complex{T}};
	tol_hard=1e-4) where {T}
	n = length(q)

	idx = argmax(real(λ))
	if abs(real(λ[idx])) <= 1e6*abs(imag(λ[idx])) # No more solutions...
		return zeros(T, 0), zeros(T, 0), NaN
	end
	l = real(λ[idx]);
	λ[idx] = -Inf  # This ensures that the next pop_solution! would not get the same solution.
	v = real(view(V, :, idx)) + imag(view(V, :, idx))
	v1 = view(v, 1:n); v2 = view(v, n+1:2*n)

	norm_v1 = sqrt(dot(v1, C*v1))
	if norm_v1 >= tol_hard
		x1 = -sign(q'*v2)*r*v1/norm_v1
		x2 = zeros(0)
	else
		y, residual = extract_solution_hard_case(P, q, C, l, reshape(v1/norm(v1), n, 1))
		nullspace_dim = 3
		while residual >= tol_hard*norm(q) && nullspace_dim <= 20 
			κ, W, _ = eigs(P, nev=nullspace_dim, which=:SR)
			y, residual = extract_solution_hard_case(P, q, C, l, W[:, abs.(κ .+ l) .< 1e-6])
			nullspace_dim *= 2
		end
		α = roots(Poly([y'*(C*y) - r^2, 2*(C*v2)'*y, v2'*(C*v2)]))
		x1 = y + α[1]*v2
		x2 = y + α[2]*v2
	end

	return x1, x2, l
end

function extract_solution_hard_case(P, q::AbstractVector{T}, C, λ::T, W::AbstractMatrix{T}) where {T}
	D = LinearMap{T}((x) -> P*x + λ*(C*(x + W*(W'*x))), length(q); issymmetric=true)
	y = cg(-D, q)
	return y, norm(P*y + λ*(C*y) + q)
end