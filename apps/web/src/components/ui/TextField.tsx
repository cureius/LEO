import * as React from 'react'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { cn } from '@/lib/utils'

interface TextFieldProps extends React.ComponentProps<'input'> {
  label: string
  inputClassName?: string
}

export function TextField({ label, id, className, inputClassName, ...props }: TextFieldProps) {
  const generatedId = React.useId()
  const inputId = id ?? generatedId

  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <Label htmlFor={inputId}>{label}</Label>
      <Input id={inputId} className={inputClassName} {...props} />
    </div>
  )
}
