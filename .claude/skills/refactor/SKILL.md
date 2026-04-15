---
name: refactor
description: >-
  Improve code structure while preserving behavior. Use when the user asks to
  refactor code, clean up code smells, restructure a class or function, or
  improve code quality without changing behavior.
---

# Refactor

You are an expert at improving code structure while preserving behavior. Follow these principles:

## Refactoring Golden Rules

1. **Never change behavior while refactoring** - Refactoring and feature changes are separate commits
2. **Have tests before refactoring** - If tests don't exist, write them first
3. **Make small, incremental changes** - Each step should be independently verifiable
4. **Keep the code working** - The system should pass tests after each change

## Code Smells to Identify

### Bloaters

- Long Method (> 20 lines)
- Large Class (> 200 lines)
- Primitive Obsession (using primitives instead of small objects)
- Long Parameter List (> 3 parameters)
- Data Clumps (same group of data appearing together)

### Object-Orientation Abusers

- Switch Statements (could be polymorphism)
- Parallel Inheritance Hierarchies
- Refused Bequest (subclass doesn't use parent's methods)

### Change Preventers

- Divergent Change (one class changed for multiple reasons)
- Shotgun Surgery (one change requires many class edits)
- Feature Envy (method uses another class's data excessively)

### Dispensables

- Dead Code (unused code)
- Duplicate Code
- Speculative Generality (unused abstractions)
- Comments (explaining bad code instead of fixing it)

### Couplers

- Inappropriate Intimacy (classes too intertwined)
- Message Chains (`a.b().c().d()`)
- Middle Man (class delegates everything)

## Common Refactoring Techniques

### Extract Method

```text
Before: Long function with multiple responsibilities
After:  Multiple focused functions with descriptive names
```

### Extract Class

```text
Before: Class doing too many things
After:  Multiple cohesive classes with single responsibility
```

### Replace Conditional with Polymorphism

```text
Before: Switch/if statements checking type
After:  Polymorphic method calls
```

### Introduce Parameter Object

```text
Before: Multiple related parameters
After:  Single object containing related data
```

## Safe Refactoring Process

1. **Verify tests pass** - Start with green tests
2. **Make one small change** - Apply a single refactoring
3. **Run tests** - Verify behavior unchanged
4. **Commit** - Save the working state
5. **Repeat** - Continue with next refactoring

## Backward Compatibility Strategies

When refactoring public APIs:

- Add new methods, deprecate old ones
- Use adapter pattern for interface changes
- Provide migration path documentation
- Version your APIs when breaking changes are necessary

## Output Format

When suggesting refactoring:

```markdown
## Current Issue

[Description of the code smell]

## Proposed Change

[Specific refactoring technique]

## Step-by-Step Plan

1. [First safe change]
2. [Second safe change]
   ...

## Risk Assessment

[What could break and how to verify]
```
