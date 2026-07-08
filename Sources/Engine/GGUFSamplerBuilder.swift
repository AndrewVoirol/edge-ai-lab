// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if canImport(LlamaCpp)
import LlamaCpp

// MARK: - GGUFSamplerBuilder

/// Builds a llama.cpp sampler chain from a `GenerationConfig`.
///
/// llama.cpp uses a chain of samplers applied in sequence:
/// 1. Repetition penalty (optional)
/// 2. Top-K filtering
/// 3. Top-P (nucleus) filtering
/// 4. Min-P filtering (quality floor)
/// 5. Temperature scaling
/// 6. Distribution sampling
///
/// The chain is consumed by `llama_sampler_sample()` during token generation.
enum GGUFSamplerBuilder {

    /// Build a sampler chain from generation config.
    ///
    /// - Parameters:
    ///   - config: Generation parameters (temperature, topP, topK, etc.)
    ///   - vocab: The model's vocabulary (needed for repetition penalty)
    /// - Returns: An `OpaquePointer` to the sampler chain. Caller must free with `llama_sampler_free()`.
    static func build(from config: GenerationConfig, vocab: OpaquePointer) -> OpaquePointer {
        var chainParams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(chainParams)!

        // Repetition penalty
        if let penalty = config.repetitionPenalty, penalty > 1.0 {
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(
                Int32(llama_vocab_n_tokens(vocab)),  // vocab size
                llama_vocab_eos(vocab),               // EOS token
                llama_vocab_nl(vocab),                // newline token
                64,                                    // penalty_last_n (window)
                Float(penalty),                       // penalty_repeat
                0.0,                                   // penalty_freq
                0.0,                                   // penalty_present
                false,                                 // penalize_nl
                false                                  // ignore_eos
            ))
        }

        // Top-K: only consider K most probable tokens
        if config.topK > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(config.topK)))
        }

        // Top-P (nucleus): only consider tokens with cumulative probability ≤ topP
        if config.topP < 1.0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(config.topP), 1))
        }

        // Min-P: quality floor (industry default 0.05)
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(0.05, 1))

        // Temperature
        if config.temperature > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(config.temperature)))
        }

        // Distribution sampling (greedy if temperature == 0)
        if config.temperature > 0 {
            let seed = config.seed ?? UInt64(arc4random())
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32(seed)))
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        }

        return chain
    }
}
#endif
