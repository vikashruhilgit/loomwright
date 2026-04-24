---
name: frontend-ui
description: Enforce design system components, accessibility (WCAG 2.1 AA), responsive design, and component reusability. Use when reviewing frontend/UI code in React, Vue, Angular, or Svelte projects.
allowed-tools: Read, Grep
version: "1.0.0"
lastUpdated: "2026-03"
---

# Frontend UI Skill

Enforce design system components, accessibility, responsive design, and component reusability for frontend projects.

## Quick Rules

- **Design System First:** Use design-system components over raw HTML elements
- **Accessibility:** Alt text, ARIA labels, keyboard navigation, color contrast
- **Responsive:** Mobile-first, consistent breakpoints, fluid layouts
- **Reusability:** No duplicate UI logic, extract common patterns to shared components
- **Type Safety:** Typed props for all components, no implicit `any`
- **Performance:** Code splitting, lazy loading, optimized images

---

## When to Use This Skill

**Apply this skill when reviewing:**
- React/Vue/Angular/Svelte components
- Any frontend code touching UI
- Projects with design systems or component libraries
- Accessibility-critical applications
- Responsive web applications

**Do NOT apply when:**
- Reviewing backend code (use nestjs/gateway skills instead)
- Project has no UI guidelines (falls back to CLAUDE.md patterns)
- Command-line tools or non-visual interfaces

---

## Design System Enforcement

### Rule: Use Design System Components

**DO:**
```tsx
// Good: Using design-system Button component
import { Button } from '@/components/ui/button'

export function LoginForm() {
  return (
    <form>
      <Button variant="primary" size="lg">
        Sign In
      </Button>
    </form>
  )
}
```

**DON'T:**
```tsx
// Bad: Raw HTML button bypasses design system
export function LoginForm() {
  return (
    <form>
      <button className="bg-blue-500 px-4 py-2 rounded">
        Sign In
      </button>
    </form>
  )
}
```

### When to Flag

| Pattern | Severity | Fix Suggestion |
|---------|----------|----------------|
| Raw `<button>` when `<Button>` exists | HIGH | Replace with design-system `Button` component |
| Raw `<input>` when `<Input>` exists | HIGH | Replace with design-system `Input` component |
| Inline styles when styled-components used | MEDIUM | Use styled-components or theme tokens |
| Custom dropdown when `<Select>` exists | MEDIUM | Replace with design-system `Select` |
| Hardcoded colors (not theme tokens) | MEDIUM | Use theme colors (`theme.colors.primary`) |

### How to Validate

1. **Check CLAUDE.md** for design-system references:
   - "Uses shadcn/ui component library"
   - "Material-UI (MUI) design system"
   - "Custom design system in `/components/ui/`"

2. **Grep for component library:**
   ```bash
   # Find design-system components
   ls -la src/components/ui/
   grep -r "from '@/components/ui" src/
   ```

3. **Flag violations:**
   - File: src/components/LoginForm.tsx:15
   - Issue: Using raw `<button>` instead of `<Button>` from design system
   - Fix: Import `Button` from `@/components/ui/button` and replace

---

## Accessibility (WCAG 2.1 AA)

### Critical Accessibility Checks

#### 1. Images: Alt Text (Level A)

**DO:**
```tsx
// Good: Descriptive alt text
<img src="/avatar.jpg" alt="User profile avatar" />

// Good: Decorative image (empty alt)
<img src="/decorative-line.svg" alt="" role="presentation" />
```

**DON'T:**
```tsx
// Bad: Missing alt text
<img src="/avatar.jpg" />

// Bad: Non-descriptive alt
<img src="/chart.png" alt="image" />
```

#### 2. Buttons: Accessible Labels (Level A)

**DO:**
```tsx
// Good: Visible text label
<Button>Submit</Button>

// Good: Icon button with aria-label
<Button aria-label="Close dialog">
  <XIcon />
</Button>
```

**DON'T:**
```tsx
// Bad: Icon-only button without label
<Button>
  <XIcon />
</Button>

// Bad: Empty button
<Button onClick={handleClick} />
```

#### 3. Form Inputs: Labels (Level A)

**DO:**
```tsx
// Good: Explicit label association
<label htmlFor="email">Email Address</label>
<Input id="email" type="email" />

// Good: aria-label for screenreaders
<Input
  type="search"
  aria-label="Search products"
  placeholder="Search..."
/>
```

**DON'T:**
```tsx
// Bad: Input without label
<Input type="email" placeholder="Email" />

// Bad: Label not associated with input
<label>Email</label>
<Input type="email" />
```

#### 4. Color Contrast: 4.5:1 for Normal Text (Level AA)

**DO:**
```tsx
// Good: High contrast text
<p className="text-gray-900 dark:text-gray-100">
  Main content text
</p>

// Good: Using theme tokens with verified contrast
<Text variant="body" color="foreground">
  Content
</Text>
```

**DON'T:**
```tsx
// Bad: Low contrast (light gray on white)
<p className="text-gray-300">
  Hard to read text
</p>

// Bad: Custom color without contrast verification
<p style={{ color: '#aaa', background: '#fff' }}>
  Low contrast
</p>
```

#### 5. Keyboard Navigation (Level A)

**DO:**
```tsx
// Good: Keyboard-accessible interactive elements
<div
  role="button"
  tabIndex={0}
  onClick={handleClick}
  onKeyDown={(e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      handleClick()
    }
  }}
>
  Click me
</div>

// Better: Use semantic button
<button onClick={handleClick}>
  Click me
</button>
```

**DON'T:**
```tsx
// Bad: onClick without keyboard support
<div onClick={handleClick}>
  Click me
</div>

// Bad: Missing tabIndex for interactive element
<div role="button" onClick={handleClick}>
  Click me
</div>
```

### Accessibility Checklist

When reviewing UI code, verify:

- [ ] All images have meaningful `alt` text (or `alt=""` if decorative)
- [ ] Icon-only buttons have `aria-label` or `aria-labelledby`
- [ ] Form inputs have associated `<label>` or `aria-label`
- [ ] Color contrast ≥ 4.5:1 for text (verify with contrast checker)
- [ ] Interactive elements support keyboard (Enter/Space keys)
- [ ] Focus indicators visible (`:focus` styles defined)
- [ ] Modals/dialogs trap focus and have close mechanism
- [ ] Skip links provided for navigation (optional, but recommended)

### When to Flag Accessibility Issues

| Finding | Severity | Action |
|---------|----------|--------|
| Missing `alt` on content image | HIGH | Require alt text |
| Icon button without `aria-label` | HIGH | Add descriptive label |
| Input without label | HIGH | Add `<label>` or `aria-label` |
| Color contrast < 4.5:1 | MEDIUM | Suggest higher contrast color |
| `onClick` without keyboard support | MEDIUM | Add `onKeyDown` handler |
| Missing focus indicator | LOW | Suggest `:focus` styles |

---

## Responsive Design

### Mobile-First Approach

**DO:**
```tsx
// Good: Base styles for mobile, override for larger screens
<div className="
  flex flex-col gap-4
  md:flex-row md:gap-8
  lg:gap-12
">
  <Sidebar />
  <MainContent />
</div>
```

**DON'T:**
```tsx
// Bad: Desktop-first (requires overrides for mobile)
<div className="
  flex flex-row gap-12
  sm:flex-col sm:gap-4
">
  <Sidebar />
  <MainContent />
</div>
```

### Consistent Breakpoints

**Check CLAUDE.md for breakpoint definitions:**

```typescript
// Good: Centralized breakpoints (from CLAUDE.md)
const breakpoints = {
  sm: '640px',   // Mobile landscape
  md: '768px',   // Tablet
  lg: '1024px',  // Desktop
  xl: '1280px',  // Wide desktop
}
```

**Flag inconsistencies:**
- File: src/components/Header.tsx:12
- Issue: Using custom breakpoint `@media (min-width: 800px)` instead of theme breakpoint `md`
- Fix: Replace with `md:` utility or `theme.breakpoints.md`

### Fluid Layouts

**DO:**
```tsx
// Good: Responsive padding and max-width
<Container className="
  px-4 sm:px-6 lg:px-8
  max-w-7xl mx-auto
">
  <Content />
</Container>
```

**DON'T:**
```tsx
// Bad: Fixed width (not responsive)
<div style={{ width: '1200px', padding: '32px' }}>
  <Content />
</div>
```

### Responsive Images

**DO:**
```tsx
// Good: Responsive images with srcset
<img
  src="/hero-800.jpg"
  srcSet="/hero-400.jpg 400w, /hero-800.jpg 800w, /hero-1200.jpg 1200w"
  sizes="(max-width: 768px) 100vw, 800px"
  alt="Hero image"
/>

// Good: Next.js Image with automatic optimization
<Image
  src="/hero.jpg"
  alt="Hero image"
  width={1200}
  height={600}
  responsive
/>
```

**DON'T:**
```tsx
// Bad: Large image without responsive sizing
<img src="/hero-4k.jpg" alt="Hero" />
```

### Responsive Design Checklist

- [ ] Mobile-first approach (base styles for small screens)
- [ ] Breakpoints match theme/CLAUDE.md definitions
- [ ] Layouts use flexbox/grid (not fixed widths)
- [ ] Images have `srcset` or responsive component
- [ ] Text sizes scale with viewport (`clamp()` or responsive utilities)
- [ ] Touch targets ≥ 44x44px on mobile
- [ ] No horizontal scroll on mobile

---

## Component Reusability

### Extract Common Patterns

**DO:**
```tsx
// Good: Reusable Card component
export function Card({ title, children, actions }: CardProps) {
  return (
    <div className="card">
      <h3>{title}</h3>
      <div className="card-body">{children}</div>
      {actions && <div className="card-actions">{actions}</div>}
    </div>
  )
}

// Usage
<Card title="User Profile" actions={<Button>Edit</Button>}>
  <p>{user.bio}</p>
</Card>
```

**DON'T:**
```tsx
// Bad: Duplicate card markup in multiple components
export function UserProfile() {
  return (
    <div className="card">
      <h3>User Profile</h3>
      <div className="card-body">
        <p>{user.bio}</p>
      </div>
      <div className="card-actions">
        <button>Edit</button>
      </div>
    </div>
  )
}

export function ProductCard() {
  return (
    <div className="card">
      <h3>Product</h3>
      <div className="card-body">
        <p>{product.description}</p>
      </div>
      <div className="card-actions">
        <button>View</button>
      </div>
    </div>
  )
}
```

### When to Flag Duplication

| Pattern | Threshold | Action |
|---------|-----------|--------|
| Same JSX structure | 3+ times | Extract to shared component |
| Same utility class combo | 5+ times | Create component variant |
| Same event handler logic | 3+ times | Extract to custom hook |
| Same styled-component | 2+ times | Move to shared components |

### Component Composition

**DO:**
```tsx
// Good: Composable components
<Dialog>
  <DialogTrigger>
    <Button>Open</Button>
  </DialogTrigger>
  <DialogContent>
    <DialogHeader>
      <DialogTitle>Confirm Action</DialogTitle>
    </DialogHeader>
    <DialogBody>
      <p>Are you sure?</p>
    </DialogBody>
    <DialogFooter>
      <Button variant="outline">Cancel</Button>
      <Button variant="primary">Confirm</Button>
    </DialogFooter>
  </DialogContent>
</Dialog>
```

**DON'T:**
```tsx
// Bad: Monolithic component with too many props
<Dialog
  title="Confirm Action"
  body="Are you sure?"
  cancelText="Cancel"
  confirmText="Confirm"
  onCancel={handleCancel}
  onConfirm={handleConfirm}
  showHeader={true}
  showFooter={true}
  // ...20 more props
/>
```

---

## Type Safety for Components

### Typed Props

**DO:**
```tsx
// Good: Explicit prop types
interface ButtonProps {
  variant: 'primary' | 'secondary' | 'outline'
  size?: 'sm' | 'md' | 'lg'
  disabled?: boolean
  onClick?: () => void
  children: React.ReactNode
}

export function Button({
  variant,
  size = 'md',
  disabled,
  onClick,
  children
}: ButtonProps) {
  return (
    <button
      className={`btn btn-${variant} btn-${size}`}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  )
}
```

**DON'T:**
```tsx
// Bad: Props without types (implicit any)
export function Button({ variant, size, disabled, onClick, children }) {
  return (
    <button
      className={`btn btn-${variant} btn-${size}`}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  )
}

// Bad: Using `any`
export function Button(props: any) {
  // ...
}
```

### Discriminated Unions for Variants

**DO:**
```tsx
// Good: Type-safe variants with discriminated unions
type IconButtonProps = {
  variant: 'icon'
  icon: React.ReactNode
  'aria-label': string
}

type TextButtonProps = {
  variant: 'text'
  children: React.ReactNode
}

type ButtonProps = IconButtonProps | TextButtonProps

export function Button(props: ButtonProps) {
  if (props.variant === 'icon') {
    return <button aria-label={props['aria-label']}>{props.icon}</button>
  }
  return <button>{props.children}</button>
}
```

**DON'T:**
```tsx
// Bad: Optional props that should be required together
interface ButtonProps {
  variant: 'icon' | 'text'
  icon?: React.ReactNode
  children?: React.ReactNode
  'aria-label'?: string  // Should be required for icon variant!
}
```

### Generic Components

**DO:**
```tsx
// Good: Generic type for flexible data structures
interface ListProps<T> {
  items: T[]
  renderItem: (item: T) => React.ReactNode
  keyExtractor: (item: T) => string
}

export function List<T>({ items, renderItem, keyExtractor }: ListProps<T>) {
  return (
    <ul>
      {items.map((item) => (
        <li key={keyExtractor(item)}>{renderItem(item)}</li>
      ))}
    </ul>
  )
}

// Usage with full type safety
<List<User>
  items={users}
  renderItem={(user) => <UserCard user={user} />}
  keyExtractor={(user) => user.id}
/>
```

---

## Performance Considerations

### Code Splitting

**DO:**
```tsx
// Good: Lazy load heavy components
import { lazy, Suspense } from 'react'

const HeavyChart = lazy(() => import('./HeavyChart'))

export function Dashboard() {
  return (
    <Suspense fallback={<Skeleton />}>
      <HeavyChart data={chartData} />
    </Suspense>
  )
}
```

**DON'T:**
```tsx
// Bad: Import heavy library in main bundle
import { HeavyChart } from './HeavyChart'

export function Dashboard() {
  return <HeavyChart data={chartData} />
}
```

### Optimized Images

**DO:**
```tsx
// Good: Optimized, lazy-loaded images
<Image
  src="/large-image.jpg"
  alt="Large image"
  width={800}
  height={600}
  loading="lazy"
  placeholder="blur"
/>
```

**DON'T:**
```tsx
// Bad: Unoptimized, eager-loaded images
<img src="/large-image.jpg" alt="Large image" />
```

### Memoization

**DO:**
```tsx
// Good: Memoize expensive computations
const ExpensiveComponent = memo(function ExpensiveComponent({ data }: Props) {
  const computed = useMemo(() => expensiveCalculation(data), [data])
  return <div>{computed}</div>
})
```

**DON'T:**
```tsx
// Bad: Re-compute on every render
function ExpensiveComponent({ data }: Props) {
  const computed = expensiveCalculation(data)  // Runs every render!
  return <div>{computed}</div>
}
```

---

## Review Decision Matrix

| Finding | Severity | Decision | Action |
|---------|----------|----------|--------|
| Raw `<button>` instead of design-system component | HIGH | FAIL | Replace with design-system Button |
| Missing alt text on content image | HIGH | FAIL | Add descriptive alt text |
| Input without label | HIGH | FAIL | Add `<label>` or `aria-label` |
| Color contrast < 4.5:1 | MEDIUM | NEEDS_HUMAN | Suggest higher contrast (verify with designer) |
| Duplicate UI component (3+ times) | MEDIUM | NEEDS_HUMAN | Extract to shared component |
| Custom breakpoint (not theme) | MEDIUM | FAIL | Use theme breakpoints |
| Untyped component props | HIGH | FAIL | Add TypeScript interface |
| Missing `aria-label` on icon button | HIGH | FAIL | Add descriptive label |
| Fixed width layout (not responsive) | MEDIUM | NEEDS_HUMAN | Refactor to fluid layout |
| Unoptimized image (no srcset) | LOW | PASS (comment) | Suggest image optimization |

---

## Integration with Code Reviewer

### Automatic Loading

Code Reviewer loads this skill when:
- **File path patterns:**
  - `src/components/**/*.tsx`
  - `src/app/**/page.tsx` (Next.js)
  - `src/views/**/*.vue` (Vue)
  - `src/app/**/*.component.ts` (Angular)

- **CLAUDE.md indicators:**
  - "Design system: shadcn/ui"
  - "Component library: Material-UI"
  - "UI framework: Tailwind CSS"
  - "Accessibility: WCAG 2.1 AA compliance"

- **Explicit skill reference:**
  - Task acceptance criteria mentions `skills/frontend-ui/SKILL.md`

### Fallback Behavior

If **no design system defined in CLAUDE.md:**
- Skip design-system enforcement (allow raw HTML elements)
- Still enforce accessibility and responsive design
- Flag if project would benefit from design system (3+ duplicate components)

If **project has custom UI guidelines in CLAUDE.md:**
- Prioritize CLAUDE.md patterns over this skill
- Use this skill as supplementary guidance

### Disabling This Skill

To disable frontend-ui checks:
- Remove skill reference from task acceptance criteria
- Or add to CLAUDE.md: `UI_VALIDATION: disabled`

---

## Examples by Framework

### React + Tailwind + shadcn/ui

```tsx
// ✓ GOOD: Follows all frontend-ui patterns
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

interface LoginFormProps {
  onSubmit: (email: string, password: string) => void
}

export function LoginForm({ onSubmit }: LoginFormProps) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit(email, password)
      }}
      className="flex flex-col gap-4 max-w-md mx-auto p-4"
    >
      <div>
        <Label htmlFor="email">Email Address</Label>
        <Input
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          aria-required="true"
        />
      </div>

      <div>
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          aria-required="true"
        />
      </div>

      <Button type="submit" variant="primary" size="lg">
        Sign In
      </Button>
    </form>
  )
}
```

### Vue + Vuetify

```vue
<!-- ✓ GOOD: Using Vuetify components, typed props, accessible -->
<template>
  <v-card class="mx-auto" max-width="500">
    <v-card-title>User Profile</v-card-title>
    <v-card-text>
      <v-form>
        <v-text-field
          v-model="name"
          label="Full Name"
          :rules="nameRules"
          required
        />
        <v-text-field
          v-model="email"
          label="Email"
          type="email"
          :rules="emailRules"
          required
        />
      </v-form>
    </v-card-text>
    <v-card-actions>
      <v-btn color="primary" @click="handleSave">
        Save Changes
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script lang="ts">
import { defineComponent } from 'vue'

interface UserProfileData {
  name: string
  email: string
}

export default defineComponent({
  name: 'UserProfile',
  data(): UserProfileData {
    return {
      name: '',
      email: '',
    }
  },
  computed: {
    nameRules() {
      return [(v: string) => !!v || 'Name is required']
    },
    emailRules() {
      return [
        (v: string) => !!v || 'Email is required',
        (v: string) => /.+@.+\..+/.test(v) || 'Email must be valid',
      ]
    },
  },
  methods: {
    handleSave() {
      this.$emit('save', { name: this.name, email: this.email })
    },
  },
})
</script>
```

---

## Token Cost

- **Skill invocation:** 600-800 tokens (full skill content)
- **Partial checks (accessibility only):** 200-300 tokens
- **Partial checks (design-system only):** 150-250 tokens
- **Context7 (if needed for library docs):** 1000-1500 tokens
- **Total (worst case):** ~2500 tokens

**Optimization:**
- Code Reviewer loads only relevant sections based on file type
- If no design system in CLAUDE.md, skip design-system checks (saves ~200 tokens)
- If backend file, skip entirely (0 tokens)

---

## Related Skills

- `skills/nextjs-components/SKILL.md` - Next.js Server/Client component patterns
- `skills/nextjs-routing/SKILL.md` - Next.js App Router file-based routing
- `skills/quality-checklist/SKILL.md` - General code quality gates
- `skills/pattern-detector/SKILL.md` - Detecting new patterns for CLAUDE.md

---

## Version

- **Version:** 1.0.0
- **Last Updated:** January 2026
- **Maintained By:** AI Agent Manager Plugin
