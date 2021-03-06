defmodule Exfmt.Algebra do
  @moduledoc """
  A set of functions for creating and manipulating algebra
  documents.

  This module implements the functionality described in
  ["Strictly Pretty" (2000) by Christian Lindig][0], with a few
  extensions detailed below.

  [0]: http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.34.2200

  It serves an alternative printer to the one defined in
  `Inspect.Algebra`, which is part of the Elixir standard library
  but does not entirely conform to the algorithm described by Christian
  Lindig in a way that makes it unsuitable for use in ExFmt.


  ## Extensions

  - `nest/1` can take the atom `:current` instead of an integer. With
    this value the formatter will set the indentation level to the
    current column position.
  - `break/2` allows the user to specify a string that can be rendered in the
    document when the break is rendering in a flat layout. This was added to
    insert trailing newlines.
  - `break_parent/0` can be used to force all parent groups to break. Inspired
    by [Prettier][0]'s `breakParent`.

  [0]: https://github.com/prettier/prettier
  """

  alias Inspect, as: I
  require I.Algebra

  #
  # Functional interface to "doc" records
  #

  #
  # Lifted from `Inspect.Algebra.is_doc/1`
  #
  @type t
    :: :doc_nil
    | :doc_line
    | :doc_break_parent
    | doc_cons
    | doc_nest
    | doc_break
    | doc_group
    | binary

  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.doc_cons/1`
  #
  @typep doc_cons :: {:doc_cons, t, t}
  defmacrop doc_cons(left, right) do
    quote do
      {:doc_cons, unquote(left), unquote(right)}
    end
  end

  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.doc_nest/1`
  #
  # Modified to have accept `:current` value
  #
  @typep doc_nest :: {:doc_nest, t, non_neg_integer | :current}
  defmacrop doc_nest(doc, indent) do
    quote do
      {:doc_nest, unquote(doc), unquote(indent)}
    end
  end

  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.doc_break/1`
  #
  @typep doc_break :: {:doc_break, binary, binary}
  defmacrop doc_break(unbroken, broken) do
    quote do
      {:doc_break, unquote(unbroken), unquote(broken)}
    end
  end

  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.doc_group/1`
  #
  @typep doc_group :: {:doc_group, t}
  defmacrop doc_group(group) do
    quote do
      {:doc_group, unquote(group)}
    end
  end

  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.is_doc/1`
  #
  defmacrop is_doc(doc) do
    if Macro.Env.in_guard?(__CALLER__) do
      do_is_doc(doc)
    else
      var = quote do
        doc
      end
      quote do
        unquote(var) = unquote(doc)
        unquote(do_is_doc(var))
      end
    end
  end

  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.do_is_doc/1`, and then
  # extended with the new Algebra.
  #
  defp do_is_doc(doc) do
    quote do
      is_binary(unquote(doc)) or
      unquote(doc) in [:doc_nil, :doc_line, :doc_break_parent] or
      (is_tuple(unquote(doc)) and
       elem(unquote(doc), 0) in
        [:doc_cons, :doc_nest, :doc_break, :doc_group])
    end
  end

  #
  # Public interface to algebra
  #

  defdelegate empty(), to: I.Algebra
  defdelegate fold_doc(docs, fun), to: I.Algebra
  defdelegate line(doc1, doc2), to: I.Algebra
  defdelegate space(doc1, doc2), to: I.Algebra


  @doc """
  Converts an Elixir term to an algebra document
  according to the `Inspect` protocol.

  """
  @spec to_doc(term) :: t
  def to_doc(term) do
    Inspect.Algebra.to_doc(term, %Inspect.Opts{})
  end


  @doc ~S"""
  Returns a document entity representing a break based on the given
  `string`.

  This break can be rendered as a `broken` followed by a linebreak and or as
  the given `unbroken`, depending on the `mode` of the chosen layout or the
  provided separator.

  ## Examples

  Let's create a document by concatenating two strings with a break between
  them:

      iex> doc = Inspect.Algebra.concat(["a", Inspect.Algebra.break("\t"), "b"])
      iex> Inspect.Algebra.format(doc, 80)
      ["a", "\t", "b"]

  Notice the break was represented with the given string, because we didn't
  reach a line limit. Once we do, it is replaced by a newline:

      iex> break = Inspect.Algebra.break("\t")
      iex> doc = Inspect.Algebra.concat([String.duplicate("a", 20), break, "b"])
      iex> Inspect.Algebra.format(doc, 10)
      ["aaaaaaaaaaaaaaaaaaaa", "\n", "b"]

  """
  @spec break(binary, binary) :: doc_break
  def break(unbroken, broken) when is_binary(unbroken) and is_binary(broken) do
    doc_break(unbroken, broken)
  end


  @doc ~S"""
  Returns a document entity with the `" "` string as break.

  See `break/2` for more information.
  """
  @spec break(binary) :: doc_break
  def break(unbroken) do
    doc_break(unbroken, "")
  end


  @doc ~S"""
  Returns a document entity with the `" "` string as break.

  See `break/2` for more information.
  """
  @spec break :: doc_break
  def break do
    doc_break(" ", "")
  end


  @doc ~S"""
  Forces all parent groups to break.

  """
  @spec break_parent :: :doc_break_parent
  def break_parent do
    :doc_break_parent
  end


  @doc ~S"""
  Maps and glues a collection of items.

  It uses the given `left` and `right` documents as surrounding and the
  separator document `separator` to separate items in `docs`.

  ## Examples

      iex> doc = surround_many("[", Enum.to_list(1..5), "]", &to_string/1)
      iex> format(doc, 5) |> IO.iodata_to_binary
      "[1,\n 2,\n 3,\n 4,\n 5]"

  """
  def surround_many(open, args, close, fun)

  def surround_many(open, [], close, _) do
    concat(open, close)
  end

  def surround_many(open, args, close, fun) do
    args_doc =
      args
      |> Enum.map(fun)
      |> Enum.reduce(fn(e, acc) ->
        glue(concat(acc, ","), e)
      end)
    surround(open, args_doc, close)
  end


  @doc ~S"""
  Concatenates two document entities returning a new document.

  ## Examples

      iex> doc = concat("hello", "world")
      ...> format(doc, 80)
      ["hello", "world"]

  """
  @spec concat(t, t) :: t
  def concat(doc1, doc2) when is_doc(doc1) and is_doc(doc2) do
    doc_cons(doc1, doc2)
  end


  @doc ~S"""
  Concatenates a list of documents returning a new document.

  ## Examples

      iex> doc = concat(["a", "b", "c"])
      ...> format(doc, 80)
      ["a", "b", "c"]

  """
  @spec concat([t]) :: t
  def concat(docs) when is_list(docs) do
    fold_doc(docs, &concat(&1, &2))
  end


  @doc """
  Insert a new line

  """
  @spec line :: t
  def line do
    :doc_line
  end


  @doc ~S"""
  Glues two documents together inserting `" "` as a break between them.

  This means the two documents will be separated by `" "` in case they
  fit in the same line. Otherwise a line break is used.

  ## Examples

      iex> doc = glue("hello", "world")
      ...> format(doc, 80)
      ["hello", " ", "world"]

  """
  @spec glue(t, t) :: t
  def glue(doc1, doc2) do
    concat(doc1, concat(break(), doc2))
  end

  @doc ~S"""
  Glues two documents (`doc1` and `doc2`) together inserting the given
  break `break_string` between them.

  For more information on how the break is inserted, see `break/1`.

  ## Examples

      iex> doc = glue("hello", "\t", "world")
      ...> format(doc, 80)
      ["hello", "\t", "world"]

  """
  @spec glue(t, binary, t) :: t
  def glue(doc1, break_string, doc2) when is_binary(break_string) do
    concat(doc1, concat(break(break_string), doc2))
  end


  @doc ~S"""
  Nests the given document at the given `level`.

  Nesting will be appended to the line breaks.

  ## Examples

      iex> doc = Inspect.Algebra.nest(Inspect.Algebra.glue("hello", "world"), 5)
      iex> Inspect.Algebra.format(doc, 5)
      ["hello", "\n     ", "world"]

  """
  @spec nest(t, non_neg_integer | :current) :: doc_nest
  def nest(doc, level)

  def nest(doc, 0) when is_doc(doc) do
    doc
  end

  def nest(doc, :current) do
    doc_nest(doc, :current)
  end

  def nest(doc, level) when is_doc(doc) and is_integer(level) and level > 0 do
    doc_nest(doc, level)
  end


  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.group/1`
  #
  @doc ~S"""
  Returns a group containing the specified document `doc`.
  Documents in a group are attempted to be rendered together
  to the best of the renderer ability.
  ## Examples
      iex> doc = Inspect.Algebra.group(
      ...>   Inspect.Algebra.concat(
      ...>     Inspect.Algebra.group(
      ...>       Inspect.Algebra.concat(
      ...>         "Hello,",
      ...>         Inspect.Algebra.concat(
      ...>           Inspect.Algebra.break,
      ...>           "A"
      ...>         )
      ...>       )
      ...>     ),
      ...>     Inspect.Algebra.concat(
      ...>       Inspect.Algebra.break,
      ...>       "B"
      ...>     )
      ...> ))
      iex> Inspect.Algebra.format(doc, 80)
      ["Hello,", " ", "A", " ", "B"]
      iex> Inspect.Algebra.format(doc, 6)
      ["Hello,", "\n", "A", " ", "B"]
  """
  @spec group(t) :: doc_group
  def group(doc) when is_doc(doc) do
    doc_group(doc)
  end


  @nesting 1
  #
  # Lifted from Elixir 1.4's `Inspect.Algebra.surround/3`
  #
  @doc ~S"""
  Surrounds a document with characters.
  Puts the given document `doc` between the `left` and `right` documents enclosing
  and nesting it. The document is marked as a group, to show the maximum as
  possible concisely together.
  ## Examples
      iex> doc = Inspect.Algebra.surround("[", Inspect.Algebra.glue("a", "b"), "]")
      iex> Inspect.Algebra.format(doc, 3)
      ["[", "a", "\n ", "b", "]"]
  """
  @spec surround(t, t, t) :: t
  def surround(left, doc, right) when is_doc(left) and is_doc(doc) and is_doc(right) do
    group(concat(left, concat(nest(doc, @nesting), right)))
  end

  #
  # Manipulation functions
  #

  @doc ~S"""
  Formats a given document for a given width.

  Takes the maximum width and a document to print as its arguments
  and returns an IO data representation of the best layout for the
  document to fit in the given width.

  ## Examples

      iex> doc = glue("hello", " ", "world")
      iex> format(doc, 30) |> IO.iodata_to_binary()
      "hello world"
      iex> format(doc, 10) |> IO.iodata_to_binary()
      "hello\nworld"

  """
  @spec format(t, non_neg_integer | :infinity) :: iodata
  def format(doc, width) when is_doc(doc)
                         and (width == :infinity or width >= 0) do
    format(width, 0, [{0, default_mode(width), doc_group(doc)}])
  end


  defp default_mode(:infinity) do
    :flat
  end

  defp default_mode(_) do
    :break
  end


  # Record representing the document mode to be rendered: flat or broken
  @typep mode :: :flat | :break

  @spec fits?(integer, [{integer, mode, t}]) :: boolean

  defp fits?(limit, _) when limit < 0 do
    false
  end

  defp fits?(_, []) do
    true
  end

  defp fits?(_, [{_, _, :doc_line} | _]) do
    true
  end

  defp fits?(_, [{_, _, :doc_break_parent} | _]) do
    false
  end

  defp fits?(limit, [{_, _, :doc_nil} | t]) do
    fits?(limit, t)
  end

  defp fits?(limit, [{indent, m, doc_cons(x, y)} | t]) do
    fits?(limit, [{indent, m, x} | [{indent, m, y} | t]])
  end

  # Indent is never used in `fits?/2`, why do we have clauses for it?
  defp fits?(limit, [{indent, m, doc_nest(x, :current)} | t]) do
    fits?(limit, [{indent, m, x} | t])
  end

  # Indent is never used in `fits?/2`, why do we have clauses for it?
  defp fits?(limit, [{indent, m, doc_nest(x, i)} | t]) do
    fits?(limit, [{indent + i, m, x} | t])
  end

  defp fits?(limit, [{_, _, s} | t]) when is_binary(s) do
    fits?((limit - byte_size(s)), t)
  end

  defp fits?(limit, [{_, :flat, doc_break(s, _)} | t]) do
    fits?((limit - byte_size(s)), t)
  end

  defp fits?(_, [{_, :break, doc_break(_, _)} | _]) do
    true
  end

  defp fits?(limit, [{indent, _, doc_group(x)} | t]) do
    fits?(limit, [{indent, :flat, x} | t])
  end


  @spec format(integer | :infinity, integer, [{integer, mode, t}]) :: [binary]
  defp format(_, _, []) do
    []
  end

  defp format(limit, _, [{indent, _, :doc_line} | t]) do
    [line_indent(indent) | format(limit, indent, t)]
  end

  defp format(limit, width, [{_, _, :doc_break_parent} | t]) do
    format(limit, width, t)
  end

  defp format(limit, width, [{_, _, :doc_nil} | t]) do
    format(limit, width, t)
  end

  defp format(limit, width, [{indent, mode, doc_cons(x, y)} | t]) do
    docs = [{indent, mode, x} | [{indent, mode, y} | t]]
    format(limit, width, docs)
  end

  defp format(limit, width, [{_indent, mode, doc_nest(x, :current)} | t]) do
    docs = [{width, mode, x} | t]
    format(limit, width, docs)
  end

  defp format(limit, width, [{indent, mode, doc_nest(x, extra_indent)} | t]) do
    docs = [{indent + extra_indent, mode, x} | t]
    format(limit, width, docs)
  end

  defp format(limit, width, [{_, _, s} | t]) when is_binary(s) do
    new_width = width + byte_size(s)
    [s | format(limit, new_width, t)]
  end

  defp format(limit, width, [{_, :flat, doc_break(s, _)} | t]) do
    new_width = width + byte_size(s)
    [s | format(limit, new_width, t)]
  end

  defp format(limit, _width, [{indent, :break, doc_break(_, s)} | t]) do
    [s, line_indent(indent) | format(limit, indent, t)]
  end

  defp format(limit, width, [{indent, _mode, doc_group(doc)} | t]) do
    flat_docs = [{indent, :flat, doc} | t]
    if fits?(limit - width, flat_docs) do
      format(limit, width, flat_docs)
    else
      break_docs = [{indent, :break, doc} | t]
      format(limit, width, break_docs)
    end
  end


  defp line_indent(0) do
    "\n"
  end

  defp line_indent(i) do
    "\n" <> :binary.copy(" ", i)
  end
end
