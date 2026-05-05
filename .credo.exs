%{
  configs: [
    %{
      name: "default",
      checks: [
        # These checks require broad decomposition of the legacy supervisor,
        # lifecycle, storage, and backend flows. The repo-owned strict gate
        # keeps actionable checks enabled without destabilizing those flows.
        {Credo.Check.Refactor.Apply, false},
        {Credo.Check.Refactor.CondStatements, false},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Refactor.FunctionArity, false},
        {Credo.Check.Refactor.Nesting, false},
        {Credo.Check.Refactor.RedundantWithClauseResult, false},
        {Credo.Check.Warning.StructFieldAmount, false}
      ]
    }
  ]
}
