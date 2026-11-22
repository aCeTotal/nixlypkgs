import * as React from "react"
import { cn } from "@/ui/cn"
import { Dialog as SheetPrimitive } from "radix-ui"

import { Button } from "@/ui/button"
import { ComfortableDensity } from "@/ui/density"
import { focusAfterPaint, focusFirst } from "@/ui/focus-after-paint"
import { XIcon, type LucideIcon } from "lucide-react"

type SheetSize = "default" | "md" | "lg" | "xl"

const sheetWidths: Record<SheetSize, string> = {
  default: "[--sheet-width:28rem]",
  md: "[--sheet-width:40rem]",
  lg: "[--sheet-width:48rem]",
  xl: "[--sheet-width:62rem]",
}

const SheetSettled = React.createContext(true)

type GateFocus = { wait: () => void; reveal: () => void }

// Gates park focus while waiting.
const SheetGateFocus = React.createContext<GateFocus>({ wait() {}, reveal() {} })

// Last height per deferred block.
const deferredHeights = new Map<string, number>()
const DEFERRED_FALLBACK_HEIGHT = "10rem"

function Sheet({ ...props }: React.ComponentProps<typeof SheetPrimitive.Root>) {
  return <SheetPrimitive.Root data-slot="sheet" {...props} />
}

function SheetTrigger({
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Trigger>) {
  return <SheetPrimitive.Trigger data-slot="sheet-trigger" {...props} />
}

function SheetClose({
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Close>) {
  return <SheetPrimitive.Close data-slot="sheet-close" {...props} />
}

function SheetPortal({
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Portal>) {
  return <SheetPrimitive.Portal data-slot="sheet-portal" {...props} />
}

function SheetOverlay({
  className,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Overlay>) {
  return (
    <SheetPrimitive.Overlay
      data-slot="sheet-overlay"
      className={cn(
        "fixed inset-0 z-50 bg-black/40 data-open:animate-scrim-in data-closed:animate-scrim-out motion-reduce:data-open:animate-quick-fade-in motion-reduce:data-closed:animate-quick-fade-out",
        className
      )}
      {...props}
    />
  )
}

// Content unmount ends the settle.
function SettleReset({ onReset }: { onReset: () => void }) {
  React.useEffect(() => onReset, [onReset])
  return null
}

function SheetContent({
  className,
  children,
  side = "right",
  size = "default",
  showCloseButton = true,
  onAnimationEnd,
  onOpenAutoFocus,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Content> & {
  side?: "top" | "right" | "bottom" | "left"
  size?: SheetSize
  showCloseButton?: boolean
}) {
  const [settled, setSettled] = React.useState(false)
  const reset = React.useCallback(() => setSettled(false), [])
  // Heavy content waits for slide.
  const settle = (event: React.AnimationEvent<HTMLDivElement>) => {
    onAnimationEnd?.(event)
    if (event.target !== event.currentTarget || event.currentTarget.dataset.state !== "open") return
    React.startTransition(() => setSettled(true))
  }
  const root = React.useRef<HTMLDivElement>(null)
  const waiting = React.useRef(false)
  const [gateFocus] = React.useState<GateFocus>(() => ({
    wait: () => {
      waiting.current = true
    },
    reveal: () => {
      waiting.current = false
      if (root.current && document.activeElement === root.current) focusFirst(root.current)
    },
  }))
  const focusLater = (event: Event) => {
    onOpenAutoFocus?.(event)
    if (!event.defaultPrevented) focusAfterPaint(event, () => waiting.current)
  }

  return (
    <SheetPortal>
      <SheetOverlay />
      <SheetPrimitive.Content
        data-slot="sheet-content"
        data-side={side}
        data-size={size}
        data-settled={settled || undefined}
        className={cn(
          "fixed z-50 flex flex-col bg-popover bg-clip-padding text-sm text-popover-foreground shadow-2xl outline-none will-change-transform data-[side=bottom]:inset-x-0 data-[side=bottom]:bottom-0 data-[side=bottom]:h-auto data-[side=bottom]:border-t data-[side=bottom]:[--sheet-offset:translateY(100%)] data-[side=left]:inset-y-0 data-[side=left]:left-0 data-[side=left]:h-full data-[side=left]:w-3/4 data-[side=left]:border-r data-[side=left]:[--sheet-offset:translateX(-100%)] data-[side=right]:inset-y-0 data-[side=right]:right-0 data-[side=right]:h-full data-[side=right]:w-full data-[side=right]:border-l data-[side=right]:[--sheet-offset:translateX(100%)] data-[side=top]:inset-x-0 data-[side=top]:top-0 data-[side=top]:h-auto data-[side=top]:border-b data-[side=top]:[--sheet-offset:translateY(-100%)] data-[side=left]:sm:max-w-sm data-[side=right]:sm:max-w-[min(var(--sheet-width),92vw)] data-open:animate-sheet-in data-closed:animate-sheet-out data-open:data-settled:will-change-auto motion-reduce:data-open:animate-quick-fade-in motion-reduce:data-closed:animate-quick-fade-out",
          sheetWidths[size],
          className
        )}
        ref={root}
        onAnimationEnd={settle}
        onOpenAutoFocus={focusLater}
        {...props}
      >
        <SettleReset onReset={reset} />
        <SheetGateFocus value={gateFocus}>
          <SheetSettled value={settled}>{children}</SheetSettled>
        </SheetGateFocus>
        {showCloseButton && (
          <SheetPrimitive.Close data-slot="sheet-close" asChild>
            <Button
              variant="ghost"
              className="absolute top-4 right-4 text-muted-foreground"
              size="icon"
            >
              <XIcon />
              <span className="sr-only">Lukk</span>
            </Button>
          </SheetPrimitive.Close>
        )}
      </SheetPrimitive.Content>
    </SheetPortal>
  )
}

function SheetHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="sheet-header"
      className={cn(
        "flex shrink-0 flex-col gap-1.5 border-b bg-linear-to-b from-primary/6 to-transparent py-5 pr-16 pl-4 sm:pl-6",
        className
      )}
      {...props}
    />
  )
}

function SheetBody({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <ComfortableDensity value>
      <div
        data-slot="sheet-body"
        className={cn(
          "density-comfortable flex min-h-0 flex-1 flex-col overflow-y-auto text-sm",
          className
        )}
        {...props}
      />
    </ComfortableDensity>
  )
}

type SheetSectionProps = Omit<React.ComponentProps<"section">, "title"> & {
  icon: LucideIcon
  title: React.ReactNode
  description?: React.ReactNode
  action?: React.ReactNode
}

// Alternate tones mark each block.
function SheetSection({
  icon: Icon,
  title,
  description,
  action,
  className,
  children,
  ...props
}: SheetSectionProps) {
  const headingId = React.useId()
  return (
    <section
      data-slot="sheet-section"
      aria-labelledby={headingId}
      className={cn(
        "flex flex-col gap-5 bg-popover px-4 py-5 not-last:border-b last:grow sm:px-6 sm:py-6 [&:nth-of-type(even)]:bg-surface",
        className
      )}
      {...props}
    >
      <div className="flex flex-wrap items-start gap-3">
        <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-primary/10 text-primary ring-1 ring-primary/15">
          <Icon className="size-5" aria-hidden />
        </span>
        <div className="flex min-h-9 min-w-40 flex-1 flex-col justify-center gap-0.5">
          <h3
            id={headingId}
            className="font-heading text-lg leading-tight font-semibold text-foreground"
          >
            {title}
          </h3>
          {description && (
            <p className="text-sm text-muted-foreground">{description}</p>
          )}
        </div>
        {action}
      </div>
      {children}
    </section>
  )
}

function useSheetSettled() {
  return React.useContext(SheetSettled)
}

type SheetGateProps = { ready: boolean; fallback: React.ReactNode; children: React.ReactNode }

// Late content waits for slide.
function SheetGate({ ready, fallback, children }: SheetGateProps) {
  const settled = useSheetSettled()
  const focus = React.useContext(SheetGateFocus)
  const [early] = React.useState(ready)
  const shown = ready && (early || settled)
  React.useEffect(() => {
    if (shown) return
    focus.wait()
    return focus.reveal
  }, [focus, shown])
  return shown ? children : fallback
}

// Mounts after slide, same height.
function SheetDeferred({ id, children }: { id: string; children: React.ReactNode }) {
  const settled = useSheetSettled()
  const remember = React.useCallback(
    (node: HTMLDivElement) => () => void deferredHeights.set(id, node.getBoundingClientRect().height),
    [id]
  )
  if (!settled) {
    return <div aria-hidden style={{ height: deferredHeights.get(id) ?? DEFERRED_FALLBACK_HEIGHT }} />
  }
  return (
    <div ref={remember} className="flex flex-col gap-[inherit] animate-quick-fade-in">
      {children}
    </div>
  )
}

function SheetFooter({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <ComfortableDensity value>
      <div
        data-slot="sheet-footer"
        className={cn(
          "density-comfortable mt-auto flex shrink-0 flex-col gap-3 border-t bg-muted px-4 py-4 text-sm sm:px-6",
          className
        )}
        {...props}
      />
    </ComfortableDensity>
  )
}

function SheetTitle({
  className,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Title>) {
  return (
    <SheetPrimitive.Title
      data-slot="sheet-title"
      className={cn(
        "font-heading text-xl leading-tight font-semibold tracking-tight text-foreground",
        className
      )}
      {...props}
    />
  )
}

function SheetDescription({
  className,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Description>) {
  return (
    <SheetPrimitive.Description
      data-slot="sheet-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export {
  Sheet,
  SheetTrigger,
  SheetClose,
  SheetContent,
  SheetHeader,
  SheetBody,
  SheetSection,
  SheetDeferred,
  SheetGate,
  SheetFooter,
  SheetTitle,
  SheetDescription,
  useSheetSettled,
}
