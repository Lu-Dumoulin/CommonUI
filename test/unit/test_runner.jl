include(joinpath(@__DIR__, "..", "support", "setup.jl"))

# The ShellRunner tests are the one place a unit test spawns a process:
# running the command is the unit under test. They run Julia itself rather
# than `echo`, so they also work on Windows.

@testset "Runner" begin

    @testset "ShellRunner.capture returns the command's stdout without the trailing newline" begin
        # Arrange
        runner = SSH_utils.Runner.ShellRunner()
        cmd = `$(Base.julia_cmd()) --startup-file=no -e 'println("hello runner")'`

        # Act
        output = SSH_utils.Runner.capture(runner, cmd)

        # Assert
        @test output == "hello runner"
    end

    @testset "ShellRunner.execute throws when the command fails" begin
        # Arrange
        runner = SSH_utils.Runner.ShellRunner()
        cmd = `$(Base.julia_cmd()) --startup-file=no -e 'exit(3)'`

        # Act
        call = () -> SSH_utils.Runner.execute(runner, cmd)

        # Assert
        @test_throws ProcessFailedException call()
    end

    @testset "a runner without capture fails with a message naming it" begin
        # Arrange
        runner = IncompleteRunner()

        # Act
        call = () -> SSH_utils.Runner.capture(runner, `true`)

        # Assert
        @test_throws "IncompleteRunner does not implement Runner.capture" call()
    end

    @testset "a runner without execute fails with a message naming it" begin
        # Arrange
        runner = IncompleteRunner()

        # Act
        call = () -> SSH_utils.Runner.execute(runner, `true`)

        # Assert
        @test_throws "IncompleteRunner does not implement Runner.execute" call()
    end

end
