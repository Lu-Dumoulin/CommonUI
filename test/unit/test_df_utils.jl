include(joinpath(@__DIR__, "..", "support", "setup.jl"))

@testset "DF_utils" begin

    @testset "generate_dataframe has one row per combination of values" begin
        # Arrange
        listname, listtab = two_parameter_sweep()

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test nrow(df) == prod(length.(listtab))
        @test length(Set(zip(df.alpha, df.beta))) == nrow(df)
    end

    @testset "generate_dataframe returns the rows in DF.csv order" begin
        # Arrange
        listname, listtab = two_parameter_sweep()

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test collect(zip(df.alpha, df.beta)) ==
              [(0.1, 10), (0.2, 10), (0.1, 20), (0.2, 20), (0.1, 30), (0.2, 30)]
    end

    @testset "generate_dataframe varies the first parameter fastest and the last slowest" begin
        # Arrange
        listname = ["a", "b", "c"]
        listtab = [[1, 2], [3, 4], [5, 6]]

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test df.a == [1, 2, 1, 2, 1, 2, 1, 2]
        @test df.b == [3, 3, 4, 4, 3, 3, 4, 4]
        @test df.c == [5, 5, 5, 5, 6, 6, 6, 6]
    end

    @testset "generate_dataframe turns a single-value parameter into a constant column" begin
        # Arrange
        listname = ["a", "b", "c"]
        listtab = [[1, 2], [5], ["p", "q", "r"]]

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test df.b == fill(5, 6)
        @test df.a == [1, 2, 1, 2, 1, 2]
        @test df.c == ["p", "p", "q", "q", "r", "r"]
    end

    @testset "generate_dataframe gives a one-row frame when every parameter has one value" begin
        # Arrange
        listname = ["x"]
        listtab = [[1.0]]

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test size(df) == (1, 1)
        @test df.x == [1.0]
    end

    @testset "generate_dataframe returns a frame with no rows and no columns when any parameter is empty" begin
        # Arrange
        listname = ["x", "y"]
        listtab = [[1.0, 2.0], Float64[]]

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test size(df) == (0, 0)
    end

    @testset "generate_dataframe names the columns after listname, in order" begin
        # Arrange
        listname = ["zeta", "alpha", "D"]
        listtab = [[1], [2], [3]]

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test names(df) == ["zeta", "alpha", "D"]
    end

    @testset "generate_dataframe keeps each column's element type concrete" begin
        # Arrange
        listname = ["n", "x", "label"]
        listtab = [[1, 2], [0.5, 1.5], ["p", "q"]]

        # Act
        df = DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test eltype.(eachcol(df)) == [Int, Float64, String]
    end

    @testset "generate_dataframe raises when there are more names than value lists" begin
        # Arrange
        listname = ["a", "b"]
        listtab = [[1, 2]]

        # Act
        call = () -> DF_utils.generate_dataframe(listname, listtab)

        # Assert
        @test_throws BoundsError call()
    end

    @testset "generate_dataframe raises when there are more value lists than names" begin
        # Arrange
        listname = ["a"]
        listtab = [[1, 2], [3, 4]]

        # Act
        call = () -> DF_utils.generate_dataframe(listname, listtab)

        # Assert
        # Known gap: today this silently returns 4 rows with duplicated `a`
        # values instead of raising. Tracked here rather than fixed, because
        # this commit only characterises current behaviour.
        @test_broken (try call(); false catch; true end)
    end

    @testset "isloaded reports true once the module is loaded" begin
        # Arrange
        # (setup.jl has loaded DF_utils)

        # Act
        loaded = DF_utils.isloaded()

        # Assert
        @test loaded === true
    end

end
