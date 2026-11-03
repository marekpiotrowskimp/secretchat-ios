import Testing

/// Every suite that loads a real GGUF lives under this parent: `.serialized` here keeps them from
/// running in parallel with each other, so two or three models never fight over GPU memory.
@Suite(.serialized)
enum RealModelTests {}
