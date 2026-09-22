include(joinpath(@__DIR__, "..", "support", "setup.jl"))

@testset "UI_utils" begin

    # --- parse_values --------------------------------------------------------

    @testset "parse_values reads a comma-separated list as Float64" begin
        # Arrange
        input = "1,3,5"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test result == [1.0, 3.0, 5.0]
        @test all(x -> x isa Float64, result)
    end

    @testset "parse_values expands a:b as a unit-step inclusive range" begin
        # Arrange
        input = "1:5"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test result == [1.0, 2.0, 3.0, 4.0, 5.0]
    end

    @testset "parse_values expands a:b:c as start:step:stop" begin
        # Arrange
        input = "0:0.5:2"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test result == [0.0, 0.5, 1.0, 1.5, 2.0]
    end

    @testset "parse_values mixes plain values and ranges in input order" begin
        # Arrange
        input = "1,3:5,8"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test result == [1.0, 3.0, 4.0, 5.0, 8.0]
    end

    @testset "parse_values drops blank entries and surrounding whitespace" begin
        # Arrange
        input = " 1, , 2 ,"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test result == [1.0, 2.0]
    end

    @testset "parse_values passes an unparseable token through as a String" begin
        # Arrange
        input = "a,1"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test isequal(result, Any["a", 1.0])
        @test result[1] isa AbstractString
    end

    @testset "parse_values passes an unparseable range through as a String" begin
        # Arrange
        input = "1:x"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test isequal(result, Any["1:x"])
    end

    @testset "parse_values returns an empty vector for an empty string" begin
        # Arrange
        input = ""

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test isempty(result)
    end

    @testset "parse_values always returns a Vector{Any}" begin
        # Arrange
        inputs = ["", "1,2", "0:0.5:1", "a"]

        # Act
        types = [typeof(UI_utils.parse_values(s)) for s in inputs]

        # Assert
        @test all(==(Vector{Any}), types)
    end

    @testset "parse_values raises on a range that expands to nothing" begin
        # Arrange
        input = "5:1"

        # Act
        call = () -> UI_utils.parse_values(input)

        # Assert
        @test_throws ArgumentError call()
        @test_throws "5:1" call()
    end

    @testset "parse_values raises on a zero step" begin
        # Arrange
        input = "1:0:5"

        # Act
        call = () -> UI_utils.parse_values(input)

        # Assert
        @test_throws ArgumentError call()
    end

    @testset "parse_values counts down with a negative step" begin
        # Arrange
        input = "5:-1:1"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test result == [5.0, 4.0, 3.0, 2.0, 1.0]
    end

    @testset "parse_values raises on a numeric range with more than three fields" begin
        # Arrange
        input = "1:2:3:4"

        # Act
        call = () -> UI_utils.parse_values(input)

        # Assert
        @test_throws ArgumentError call()
        @test_throws "1:2:3:4" call()
    end

    @testset "parse_values still passes a non-numeric token with many colons through" begin
        # Arrange
        input = "1:x:3:4"

        # Act
        result = UI_utils.parse_values(input)

        # Assert
        @test isequal(result, Any["1:x:3:4"])
    end

    # --- parse_to_slurm_array ------------------------------------------------

    @testset "parse_to_slurm_array keeps a plain list of integers" begin
        # Arrange
        input = "1,3,5"

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "1,3,5"
    end

    @testset "parse_to_slurm_array renders a:b as a-b" begin
        # Arrange
        input = "1:5"

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "1-5"
    end

    @testset "parse_to_slurm_array renders a:b:c as a-c:b" begin
        # Arrange
        input = "1:2:9"

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "1-9:2"
    end

    @testset "parse_to_slurm_array mixes plain values and ranges in input order" begin
        # Arrange
        input = "1,3:5,8"

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "1,3-5,8"
    end

    @testset "parse_to_slurm_array drops blank entries and surrounding whitespace" begin
        # Arrange
        input = " 7 , , 8 "

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "7,8"
    end

    @testset "parse_to_slurm_array silently drops tokens that are not integers" begin
        # Arrange
        input = "1.5,2,a:3,1:x,4"

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "2,4"
    end

    @testset "parse_to_slurm_array returns an empty string for an empty string" begin
        # Arrange
        input = ""

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == ""
    end

    @testset "parse_to_slurm_array raises on a numeric range with more than three fields" begin
        # Arrange
        input = "1:2:3:4"

        # Act
        call = () -> UI_utils.parse_to_slurm_array(input)

        # Assert
        @test_throws ArgumentError call()
        @test_throws "1:2:3:4" call()
    end

    @testset "parse_to_slurm_array raises on a descending a:b" begin
        # Arrange
        input = "5:1"

        # Act
        call = () -> UI_utils.parse_to_slurm_array(input)

        # Assert
        @test_throws ArgumentError call()
    end

    @testset "parse_to_slurm_array raises on a negative step" begin
        # Arrange
        input = "5:-1:1"

        # Act
        call = () -> UI_utils.parse_to_slurm_array(input)

        # Assert
        @test_throws ArgumentError call()
    end

    @testset "parse_to_slurm_array raises on a zero step" begin
        # Arrange
        input = "1:0:5"

        # Act
        call = () -> UI_utils.parse_to_slurm_array(input)

        # Assert
        @test_throws ArgumentError call()
    end

    @testset "parse_to_slurm_array accepts a single-element range" begin
        # Arrange
        input = "3:3"

        # Act
        result = UI_utils.parse_to_slurm_array(input)

        # Assert
        @test result == "3-3"
    end

    # --- @named_parse --------------------------------------------------------

    @testset "@named_parse strips _str from names and parses those values" begin
        # Arrange
        a_str = "1,2"

        # Act
        values, names = UI_utils.@named_parse [a_str]

        # Assert
        @test names == ["a"]
        @test values == [[1.0, 2.0]]
    end

    @testset "@named_parse keeps non-_str arguments as they are" begin
        # Arrange
        zeta = 3
        D_str = "0:0.5:1"

        # Act
        values, names = UI_utils.@named_parse [zeta, D_str]

        # Assert
        @test names == ["zeta", "D"]
        @test values[1] === 3
        @test values[2] == [0.0, 0.5, 1.0]
    end

    @testset "@named_parse fails loudly when a _str value is not numeric" begin
        # Arrange
        b_str = "x"

        # Act
        call = () -> UI_utils.@named_parse [b_str]

        # Assert
        @test_throws MethodError call()
    end

    @testset "@named_parse raises at expansion time on a bare symbol" begin
        # Arrange
        expr = :(UI_utils.@named_parse a_str)

        # Act
        expand = () -> macroexpand(Main, expr)

        # Assert
        @test_throws "wrap your variables in square brackets" expand()
    end

    # --- print_list ----------------------------------------------------------

    @testset "print_list prints one name: value line per field" begin
        # Arrange
        listname = ["a", "b"]
        listvalue = [[1, 2], 3.0]

        # Act
        _, output = capture_stdout(() -> UI_utils.print_list(listname, listvalue))

        # Assert
        @test output == "a: [1, 2]\nb: 3.0\n"
    end

    @testset "print_list returns empty Markdown when every field is filled" begin
        # Arrange
        listname = ["a"]
        listvalue = [[1]]

        # Act
        result, _ = capture_stdout(() -> UI_utils.print_list(listname, listvalue))

        # Assert
        @test result isa UI_utils.Markdown.MD
    end

    @testset "print_list shows an alert and prints nothing when a field is empty" begin
        # Arrange
        listname = ["a", "b"]
        listvalue = [[1, 2], Float64[]]

        # Act
        result, output = capture_stdout(() -> UI_utils.print_list(listname, listvalue))

        # Assert
        @test output == ""
        @test !(result isa UI_utils.Markdown.MD)
        @test occursin("One field is empty", repr(MIME("text/html"), result))
    end

end
