const FOCUSABLE = "a[href], button, input, select, textarea, [tabindex]"

// Same choice as Radix autofocus.
export function focusFirst(root: HTMLElement) {
  for (const element of root.querySelectorAll<HTMLElement>(FOCUSABLE)) {
    if (element.tabIndex < 0) continue
    element.focus({ preventScroll: true })
    if (document.activeElement === element) return
  }
  root.focus({ preventScroll: true })
}

// Focus waits past first paint.
export function focusAfterPaint(event: Event, waiting: () => boolean) {
  event.preventDefault()
  const root = event.currentTarget as HTMLElement
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      if (root.contains(document.activeElement)) return
      if (waiting()) root.focus({ preventScroll: true })
      else focusFirst(root)
    })
  )
}
