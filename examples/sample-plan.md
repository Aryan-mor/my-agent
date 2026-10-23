# Plan: sample-greet-r1

Goal: tiny smoke test for my-agent. Add a `greet()` function and a unit test for it.
Run from a scratch project folder that already contains `hello/greet.py`
(see SETUP.md, "Smoke test"); `hello/test_greet.py` is a new file.

## Steps

1. `hello/greet.py`: replace the placeholder with `def greet(name: str) -> str` that returns
   `"Hello, <name>!"`; an empty or whitespace-only name returns `"Hello, world!"`.
   - done-check: `python -c "from hello.greet import greet; assert greet('Ada') == 'Hello, Ada!'"`
2. `hello/test_greet.py` (new): `unittest` tests for a normal name and for the empty-name case.
   - done-check: `python -m unittest hello.test_greet -v`

## Constraints / out of scope
- Standard library only. Do not add other files except `hello/__init__.py` if imports need it.
- Do not commit or push.

## Final verification
- `python -m unittest discover -s hello -t . -v`

## Progress checklist format (what the orchestrator writes to .opencode/progress.md)

```markdown
# Progress: sample-greet-r1
- [ ] 1. hello/greet.py: greet() with empty-name fallback | done-check: python -c "..."
- [ ] 2. hello/test_greet.py: unittest for both cases | done-check: python -m unittest hello.test_greet -v
- [ ] 3. Final verification: python -m unittest discover -s hello -t . -v
Notes / decisions:
- (none yet)
```

`delegate.ps1 wait` counts lines starting with `- [x]` as done and `- [ ]` as open, and surfaces
lines containing "blocker", "blocked" or "failed".
