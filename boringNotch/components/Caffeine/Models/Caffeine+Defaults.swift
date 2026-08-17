//
//  Caffeine+Defaults.swift
//  boringNotch
//

import Defaults

// Conformances live here rather than on the types themselves so the models stay free of
// the Defaults dependency and can be compiled and tested in isolation.
extension CaffeineMode: Defaults.Serializable {}
extension CaffeineDuration: Defaults.Serializable {}
