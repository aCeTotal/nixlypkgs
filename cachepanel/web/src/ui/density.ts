import { createContext, useContext } from "react"

// Carries sheet scale into portals.
export const ComfortableDensity = createContext(false)

export function useDensityClass() {
  return useContext(ComfortableDensity) ? "density-comfortable" : undefined
}
