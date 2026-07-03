# Contributing to env.zig

Thank you for your interest in contributing to env.zig! This document provides guidelines and instructions for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a feature branch: `git checkout -b my-feature`
4. Make your changes
5. Run tests: `zig build test`
6. Commit your changes
7. Push to your fork and submit a pull request

## Development

### Prerequisites

- Zig 0.16.0 or later

### Building

```bash
zig build
```

### Running Tests

```bash
zig build test --summary all
```

### Running Examples

```bash
zig build example
```

### Code Style

- Follow Zig's standard formatting: `zig fmt src/`
- No comments unless explicitly requested
- Every allocation must have a matching `deinit`
- No global mutable state
- All functions must be allocator-aware

## Pull Request Guidelines

- Keep changes focused and minimal
- Include tests for new functionality
- Update documentation if adding/changing public API
- Ensure all tests pass before submitting
- Write clear commit messages

## Reporting Issues

- Use GitHub Issues
- Include a minimal reproduction case
- Specify your Zig version
- Include OS/architecture information

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
