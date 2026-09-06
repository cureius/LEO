import { useRef, useState } from 'react'
import { toast } from 'sonner'
import { Upload } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { uploadProjectPdf, type ProjectPdf } from '@/domain/projectPdfs'

export function PdfUploadButton({ projectName, onUploaded }: { projectName: string; onUploaded: (pdf: ProjectPdf) => void }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)

  async function handleFile(file: File | undefined) {
    if (!file) return
    if (file.type !== 'application/pdf') {
      toast.error('Only PDF files can be uploaded here.')
      return
    }
    setUploading(true)
    try {
      const pdf = await uploadProjectPdf(projectName, file)
      onUploaded(pdf)
      toast.success(`Uploaded "${file.name}"`)
    } catch (err) {
      toast.error("Couldn't upload PDF", { description: err instanceof Error ? err.message : String(err) })
    } finally {
      setUploading(false)
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  return (
    <>
      <input
        ref={inputRef}
        type="file"
        accept="application/pdf"
        className="hidden"
        onChange={(e) => void handleFile(e.target.files?.[0])}
      />
      <Button type="button" size="sm" disabled={uploading} onClick={() => inputRef.current?.click()}>
        <Upload className="h-3.5 w-3.5" aria-hidden="true" />
        {uploading ? 'Uploading…' : 'Upload PDF'}
      </Button>
    </>
  )
}
