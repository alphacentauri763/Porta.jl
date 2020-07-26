using StatsBase
using FileIO
using Makie
using CSV
using Porta


"""
    π(p)

Map the point `p` from S³ into the Riemann sphere.
"""
function π(p::ℍ)
    z₁ = Complex(vec(p)[1], vec(p)[2])
    z₂ = Complex(vec(p)[3], vec(p)[4])
    z = z₂ / z₁
    Geographic(ComplexLine(z))
end


"""
    f(p)

Map from S² into the upper hemisphere of S² with the given point `p`.
"""
function f(p::Geographic)
    ϕ, θ = p.ϕ, p.θ
    r = sqrt((1 - sin(θ)) / 2)
    r .* (cos(ϕ), sin(ϕ))
end


"""
sample(dataframe, max)

Samples points from a dataframe with the given dataframe and the maximum number
of samples limit. The second column of the dataframe should contain longitudes
and the third one latitudes (in degrees.)
"""
function sample(dataframe, max)
    total_longitudes = dataframe[dataframe[:shapeid].<0.1, 2] ./ 180 .* pi
    total_latitudes = dataframe[dataframe[:shapeid].<0.1, 3] ./ 180 .* pi
    sampled_longitudes = Array{Float64}(undef, max)
    sampled_latitudes = Array{Float64}(undef, max)
    count = length(total_longitudes)
    if count > max
        sample!(total_longitudes,
                sampled_longitudes,
                replace=false,
                ordered=true)
        sample!(total_latitudes,
                sampled_latitudes,
                replace=false,
                ordered=true)
        longitudes = sampled_longitudes
        latitudes = sampled_latitudes
    else
        longitudes = total_longitudes
        latitudes = total_latitudes
    end
    count = length(longitudes)
    points = Array{Geographic,1}(undef, count)
    for i in 1:count
        points[i] = Geographic(longitudes[i], latitudes[i])
    end
    points
end


"""
    build(scene, surface, color)

Build a surface with the given `scene`, `surface` and `color`.
"""
function build(scene, surface, color)
    x = Node(map(x -> vec(x)[1] , surface[:, :]))
    y = Node(map(x -> vec(x)[2] , surface[:, :]))
    z = Node(map(x -> vec(x)[3] , surface[:, :]))
    surface!(scene, x, y, z, color = color)
    x, y, z
end


"""
    pullback(p, α)

Calculate the pullback to S³ with the given point `p` and the given angle `α`.
"""
function pullback(p::Geographic, α::Real, angle::Real=0)
    ϕ, θ = p.ϕ, p.θ
    ϕ = ϕ - angle
    r = sqrt((1 - sin(θ)) / 2)
    ϕ, θ = r .* (cos(ϕ), sin(ϕ))
    ϕ, θ = ϕ + pi, (θ + pi / 2) / 2
    ℍ(sin(θ) * exp(im * (ϕ + α) / 2), cos(θ) * exp(im * (α - ϕ) / 2))
end


α₁ = 0
α₂ = 2(2pi - 80 / 180 * pi)


"""
    getsurface(q, p, s)

Calculate a pullback surface using stereographic projection with the given S² rotation `q`,
an array of points 'p' and the number of segments `s`.
"""
function getsurface(τ::Real, q::ℍ, p::Array{Geographic,1}, s::Int64)
    number = length(p)
    surface = Array{ℝ³}(undef, s, number)
    lspace = range(α₁, stop = α₂, length = s)
    for (i, α) in enumerate(lspace)
        for j in 1:number
            surface[i, j] = σ(rotate(q, pullback(p[j], α, τ)))
        end
    end
    surface
end


"""
    S²(q, α)

Calculate a Riemann sphere with the given S² rotation `q` and circle `α`.
"""
function S²(q::ℍ, α::Real, segments::Int=30)
    longitudeoffset = 0.02 * pi
    latitudeoffset = -pi / 3
    s2 = Array{ℝ³}(undef, segments, segments)
    lspace = collect(range(-pi, stop = pi, length = segments)) #.+ longitudeoffset
    lspace2 = collect(range(pi / 2, stop = latitudeoffset, length = segments))
    for (i, θ) in enumerate(lspace2)
        for (j, ϕ) in enumerate(lspace)
            h = pullback(Geographic(ϕ, θ), α, 0)
            s2[i, j] = σ(rotate(q, h))
        end
    end
    s2
end


# Made with Natural Earth.
# Free vector and raster map data @ naturalearthdata.com.
countries = Dict("iran" => [0.0, 1.0, 0.29], # green
                 "us" => [0.494, 1.0, 0.0], # green
                 "china" => [1.0, 0.639, 0.0], # orange
                 "ukraine" => [0.0, 0.894, 1.0], # cyan
                 "australia" => [1.0, 0.804, 0.0], # orange
                 "germany" => [0.914, 0.0, 1.0], # purple
                 "israel" => [0.0, 1.0, 0.075]) # green
# The path to the dataset
path = "test/data/natural_earth_vector"

# The scene object that contains other visual objects
scene = Scene(backgroundcolor = :white, show_axis=false, resolution = (360, 360),
              camera = cam3d_cad!)
# Use a slider for rotating the base space in an interactive way
#sg, og = textslider(0:0.05:2pi, "g", start = 0)
# Instantiate a horizontal box for holding the visuals and the controls
#scene = hbox(universe,
#             vbox(sg),
#             parent = Scene(resolution = (360, 360)))

# The maximum number of points to sample from the dataset for each country
maxsamples = 300
segments = 30
q = ℍ(α₁, ℝ³(0, 0, 1))
observables = []
points = []
for country in countries
    dataframe = CSV.read(joinpath(path, "$(country[1])-nodes.csv"))
    # Sample a random subset of the points
    p = sample(dataframe, maxsamples)
    color = fill(RGBAf0(country[2]..., 1.0), segments, length(p))
    x, y, z = build(scene, getsurface(0, q, p, segments), color)
    push!(observables, (x, y, z))
    push!(points, p)
end


s2color = load("test/data/BaseMap.png")
s2observables = build(scene, S²(q, α₁, segments), s2color)
s2observables2 = build(scene, S²(q, α₂, segments), s2color)

frames = 90
function animate(i)
    τ = i / frames * 2pi
    for (p, nodes) in zip(points, observables)
        x, y, z = nodes
        surface = getsurface(τ, ℍ(0, ℝ³(0, 0, 1)), p, segments)
        x[] = map(i -> vec(i)[1] , surface[:, :])
        y[] = map(i -> vec(i)[2] , surface[:, :])
        z[] = map(i -> vec(i)[3] , surface[:, :])
    end
    x, y, z = s2observables
    s2 = S²(ℍ(τ, ℝ³(0, 0, 1)), τ + α₁, segments)
    x[] = map(i -> vec(i)[1] , s2[:, :])
    y[] = map(i -> vec(i)[2] , s2[:, :])
    z[] = map(i -> vec(i)[3] , s2[:, :])
    x, y, z = s2observables2
    s2 = S²(ℍ(τ, ℝ³(0, 0, 1)), τ + α₂, segments)
    x[] = map(i -> vec(i)[1] , s2[:, :])
    y[] = map(i -> vec(i)[2] , s2[:, :])
    z[] = map(i -> vec(i)[3] , s2[:, :])
end


# update eye position
# scene.camera.eyeposition.val
upvector = Vec3f0(1, 0, 1)
eyeposition = 0.8 .* Vec3f0(1, 3, 0)
lookat = Vec3f0(0.5, 0, 0)
update_cam!(scene, eyeposition, lookat, upvector)
scene.center = false # prevent scene from recentering on display

record(scene, "gallery/DrorBarNatan2010.gif") do io
    for i in 1:frames
        animate(i)
        recordframe!(io) # record a new frame
    end
end