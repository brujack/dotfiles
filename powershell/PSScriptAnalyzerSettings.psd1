@{
  ExcludeRules = @(
    # The official Chocolatey bootstrapper uses Invoke-Expression — cannot be changed
    'PSAvoidUsingInvokeExpression'
  )
}
