import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { Toaster } from 'sonner'
import { AuthProvider } from '@/auth/AuthProvider'
import { RequireAuth } from '@/auth/RequireAuth'
import { AppShell } from '@/components/layout/AppShell'
import { useSwipeNavigation } from '@/lib/useSwipeNavigation'
import { LoginPage } from '@/routes/LoginPage'
import { SignUpPage } from '@/routes/SignUpPage'
import { ForgotPasswordPage } from '@/routes/ForgotPasswordPage'
import { ResetPasswordPage } from '@/routes/ResetPasswordPage'
import { DashboardPage } from '@/routes/DashboardPage'
import { TodayPage } from '@/routes/TodayPage'
import { InboxPage } from '@/routes/InboxPage'
import { HabitsPage } from '@/routes/HabitsPage'
import { FitnessPage } from '@/routes/FitnessPage'
import { ProjectsPage } from '@/routes/ProjectsPage'
import { ProjectDetailPage } from '@/routes/ProjectDetailPage'
import { ProjectPdfsPage } from '@/routes/ProjectPdfsPage'
import { JiraPage } from '@/routes/JiraPage'
import { SettingsPage } from '@/routes/SettingsPage'
import { DebugPage } from '@/routes/DebugPage'
import { GoogleOAuthCallbackPage } from '@/routes/GoogleOAuthCallbackPage'

// Lazy-loaded: pulls in the entire ai/ subsystem (Claude client, tool
// registry, diff review), the single largest contributor to bundle size,
// and only 1 of 5 authenticated routes ever needs it.
const ChatPage = lazy(() => import('@/routes/ChatPage').then((m) => ({ default: m.ChatPage })))

// Lazy-loaded: pulls in pdfjs-dist + pdf-lib, both heavy, and only the PDF
// viewer route ever needs them.
const PdfViewerPage = lazy(() => import('@/routes/PdfViewerPage').then((m) => ({ default: m.PdfViewerPage })))

function SwipeNavigation() {
  useSwipeNavigation()
  return null
}

function App() {
  return (
    <BrowserRouter>
      <SwipeNavigation />
      <AuthProvider>
        <Toaster richColors position="top-right" />
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/sign-up" element={<SignUpPage />} />
          <Route path="/forgot-password" element={<ForgotPasswordPage />} />
          <Route path="/reset-password" element={<ResetPasswordPage />} />

          <Route element={<RequireAuth />}>
            <Route path="/oauth/google/callback" element={<GoogleOAuthCallbackPage />} />
            <Route element={<AppShell />}>
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/today" element={<TodayPage />} />
              <Route path="/inbox" element={<InboxPage />} />
              <Route path="/habits" element={<HabitsPage />} />
              <Route path="/projects" element={<ProjectsPage />} />
              <Route path="/projects/:name" element={<ProjectDetailPage />} />
              <Route path="/projects/:name/pdfs" element={<ProjectPdfsPage />} />
              <Route
                path="/projects/:name/pdfs/:pdfId"
                element={
                  <Suspense fallback={<div className="p-6 text-sm text-text-secondary">Loading…</div>}>
                    <PdfViewerPage />
                  </Suspense>
                }
              />
              <Route path="/fitness" element={<FitnessPage />} />
              <Route path="/jira" element={<JiraPage />} />
              <Route path="/settings" element={<SettingsPage />} />
              <Route path="/debug" element={<DebugPage />} />
              <Route
                path="/chat"
                element={
                  <Suspense fallback={<div className="p-6 text-sm text-text-secondary">Loading…</div>}>
                    <ChatPage />
                  </Suspense>
                }
              />
            </Route>
          </Route>

          <Route path="/" element={<Navigate to="/today" replace />} />
          <Route path="*" element={<Navigate to="/today" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  )
}

export default App
