defmodule EctoAutoslugField.SlugBase do
  @moduledoc """
  This module defines all functions `Slug` module uses.
  """

  alias Ecto.Changeset
  alias EctoAutoslugField.SlugGenerator

  @doc """
  This function is used to generate slug.

  It is called 'maybe' since it may not generate slug for several reasons:

    1. It was already created and `:always_change` option was not set
    2. The source fields for the slug were empty

  This function takes changeset as an input and returns changeset.
  """
  @spec maybe_generate_slug(Changeset.t(), atom() | list() | none, Keyword.t()) ::
          Changeset.t()
  def maybe_generate_slug(changeset, sources, opts) do
    SlugGenerator.maybe_generate_slug(changeset, sources, opts)
  end

  @doc """
  This is just a helper function to check for uniqueness.

  It basically just wraps `Ecto.Changeset` and set a proper field name.
  """
  @spec unique_constraint(Changeset.t(), atom(), Keyword.t()) :: Changeset.t()
  def unique_constraint(changeset, to, opts \\ []) do
    Changeset.unique_constraint(changeset, to, opts)
  end

  @doc """
  This function is used to get sources for the slug.

  There can be many usecases when this behavior is required,
  here are the brief examples:

    1. Conditional slug sources
    2. Add any data from different sources

  This function should return `list` of atoms or binaries, or `nil`.

  When processing the returned list:

    1. `atom`-key is supposed to identify the model field
    2. `binary`-key is treated as a data itself, it won't be changed
  """
  @spec get_sources(Changeset.t(), Keyword.t()) ::
          list(atom() | binary()) | none
  def get_sources(_changeset, [from: from] = _opts) do
    [from]
  end

  @doc """
  This function is used to build the slug itself.

  This function is a place to modify the result slug.
  For convenience you can call `super(sources, changeset)`
  which will return the slug binary.
  `super(sources)` uses [`Slugger`](https://github.com/h4cc/slugger),
  but you can completely change slug-engine to your own.

  Note: this function will only be called if `sources` is not empty.
  Also important this function will be called only
  once for the normal workflow. And every time for `:always_change`.
  So you can do some heavy computations.

  If for some reason slug should not be set -
  just return `nil` or empty `binary`.

  It should return a `binary` or `nil`.
  """
  @spec build_slug(Keyword.t(), Changeset.t() | nil) :: String.t()
  def build_slug(sources, changeset),
    do: SlugGenerator.build_slug(sources, changeset)
end

defmodule EctoAutoslugField.Slug do
  @moduledoc ~S"""
  This module defines all the required functions and modules to work with.

  ## Examples

  To create a simple 'Slug' field do:

      defmodule MyCustomSlug do
        use EctoAutoslugField.Slug, from: :name_field, to: :slug_field
      end

  It is also possible to override `get_sources/2` and `build_slug/2` functions
  which are part of the AutoslugField's API.

  More complex example with the optional sources
  and custom slug generation function:

      defmodule MyComplexSlug do
        use EctoAutoslugField.Slug, to: :slug_field

        def get_sources(changeset, _opts) do
          basic_fields = [:name, :surname]

          if is_company_info_set(changeset) do
            # We want to track changes in the person's company:
            basic_fields ++ [:company, :position]
          else
            basic_fields
          end
        end

        def build_slug(sources, changeset) do
          super(sources, changeset)  # Calls the `SlugGenerator.build_slug/1`
          |> String.replace("-", "+")
        end
      end

  It is also possible to always change your slug, even if it was already set:

      defmodule ThisSlugShouldChange do
        use EctoAutoslugField.Slug, from: :some_field,
          to: :slug_field, always_change: true
      end

  If you want to change slug for only one instance
  without setting `always_change` option, use `force_generate_slug/1` function:

      defmodule SimpleSlugForce do
        use EctoAutoslugField.Slug, from: :name, to: :some_slug
      end

  Then you can use `SimpleSlugForce.force_generate_slug(changeset)`
  for any instances, that needs to recreate slugs for some reason.

  Be careful with these options, since
  [cool URIs do not change](https://www.w3.org/Provider/Style/URI.html).
  """

  defmacro __using__(options) do
    caller = __CALLER__.module

    quote location: :keep, bind_quoted: [options: options, caller: caller] do
      alias EctoAutoslugField.SlugBase

      # Opts:

      @from Keyword.get(options, :from, nil)
      @to Keyword.get(options, :to, :slug)
      @always_change Keyword.get(options, :always_change, false)

      # Custom Type:

      defmodule Module.concat(caller, "Type") do
        @moduledoc """
        This module represent the auto-generated `Ecto.Type` for slug-field.

        It basically just calls the methods of the basic `Type` module.
        """
        use Ecto.Type

        alias EctoAutoslugField.Type

        def type, do: Type.type()
        def cast(value), do: Type.cast(value)
        def load(value), do: Type.load(value)
        def dump(value), do: Type.dump(value)
      end

      defp generate_slug_opts do
        [
          from: @from,
          to: @to,
          always_change: @always_change,
          slug_builder: &build_slug/2
        ]
      end

      defp generate_slug_sources(changeset, opts) do
        if opts[:from] == nil do
          get_sources(changeset, opts)
        else
          @from
        end
      end

      # Public functions:

      def maybe_generate_slug(changeset) do
        opts = generate_slug_opts()
        sources = generate_slug_sources(changeset, opts)

        SlugBase.maybe_generate_slug(changeset, sources, opts)
      end

      def force_generate_slug(changeset) do
        opts = generate_slug_opts() |> Keyword.put(:always_change, true)
        sources = generate_slug_sources(changeset, opts)

        SlugBase.maybe_generate_slug(changeset, sources, opts)
      end

      def unique_constraint(changeset, opts \\ []) do
        SlugBase.unique_constraint(changeset, @to, opts)
      end

      # Client API:

      def get_sources(changeset, opts) do
        SlugBase.get_sources(changeset, opts)
      end

      def build_slug(sources) do
        SlugBase.build_slug(sources, nil)
      end

      def build_slug(sources, _changeset) do
        build_slug(sources)
      end

      defoverridable get_sources: 2, build_slug: 2, build_slug: 1
    end
  end
end
