@{
  ExcludeRules = @(
    # The official Chocolatey bootstrapper uses Invoke-Expression — cannot be changed
    'PSAvoidUsingInvokeExpression'
    # Set-WindowsOption is a simple utility function in a dotfiles script; ShouldProcess boilerplate is unnecessary
    'PSUseShouldProcessForStateChangingFunctions'
  )
}
