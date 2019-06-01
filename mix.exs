defmodule Rafty.MixProject do
  use Mix.Project

  @github_url "https://github.com/jeffrey-xiao/rafty_ex"
  @gitlab_url "https://gitlab.com/jeffrey-xiao/rafty_ex"

  def project() do
    [
      app: :rafty,
      name: "rafty",
      version: "0.1.0",
      description: "An implementation of the Raft consensus algorithm.",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      source_url: @gitlab_url,
      homepage_url: @gitlab_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application() do
    [
      mod: {Rafty, []},
      extra_applications: [:logger]
    ]
  end

  defp deps() do
    [
      {:dialyxir, "~> 1.0.0-rc.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp package() do
    [
      files: ["lib", "LICENSE-APACHE", "LICENSE-MIT", "mix.exs", "README.md"],
      licenses: ["Apache 2.0", "MIT"],
      links: %{
        "GitHub" => @github_url,
        "GitLab" => @gitlab_url
      }
    ]
  end
end
