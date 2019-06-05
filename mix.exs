defmodule Rafty.MixProject do
  use Mix.Project

  @github_url "https://github.com/jeffrey-xiao/rafty_ex"
  @gitlab_url "https://gitlab.com/jeffrey-xiao/rafty_ex"

  def project() do
    [
      app: :rafty,
      version: "0.1.0",
      description: "An implementation of the Raft consensus algorithm.",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "rafty",
      source_url: @gitlab_url,
      homepage_url: @gitlab_url,
      docs: [
        extras: ["README.md"]
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],
      dialyzer: [
        plt_add_deps: :transitive
      ]
    ]
  end

  def application() do
    [
      mod: {Rafty, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(env) do
    case env do
      :test -> ["lib", "test/rafty_test"]
      _ -> ["lib"]
    end
  end

  defp deps() do
    [
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.6", only: :dev, runtime: false},
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
