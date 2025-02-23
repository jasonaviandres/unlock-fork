import useTermsOfService from '~/hooks/useTermsOfService'
import { useConfig } from '~/utils/withConfig'
import Loading from '../Loading'
import { Button, Modal } from '@unlock-protocol/ui'
import { AppHeader } from '../AppHeader'
import { Container } from '../Container'
import { useAuth } from '~/contexts/AuthenticationContext'
import Link from 'next/link'
import { useState, useEffect } from 'react'
import { ImageBar } from '../locks/Manage/elements/ImageBar'
import React from 'react'
// import { EMAIL_SUBSCRIPTION_FORM } from '~/constants'
// import { config } from '~/config/app'

interface DashboardLayoutProps {
  title?: string
  description?: React.ReactNode
  children: React.ReactNode
  authRequired?: boolean
  showLinks?: boolean
  showHeader?: boolean
}

export const WalletNotConnected = () => {
  const [loginUrl, setLoginUrl] = useState<string>('')
  useEffect(() => {
    setLoginUrl(`/login?redirect=${encodeURIComponent(window.location.href)}`)
  }, [])

  return (
    <ImageBar
      src="/images/illustrations/wallet-not-connected.svg"
      description={
        <>
          <span>
            Wallet is not connected yet.{' '}
            <Link href={loginUrl}>
              <span className="cursor-pointer text-brand-ui-primary">
                Connect it now
              </span>
            </Link>
          </span>
        </>
      }
    />
  )
}

// const FOOTER = {
//   subscriptionForm: {
//     title: 'Sign up for Updates',
//     description:
//       'Receive fresh news about Unlock, including new features and opportunities to contribute',
//     onSubmit: async (email: string) => {
//       const { portalId, formGuid } = EMAIL_SUBSCRIPTION_FORM
//       const endpoint = `https://api.hsforms.com/submissions/v3/integration/submit/${portalId}/${formGuid}`
//       const options = {
//         method: 'POST',
//         headers: {
//           'Content-Type': 'application/json',
//         },
//         body: JSON.stringify({
//           fields: [
//             {
//               name: 'email',
//               value: email,
//             },
//           ],
//         }),
//       }

//       await fetch(endpoint, options)
//     },
//   },
//   logo: {
//     url: config.unlockStaticUrl,
//   },
//   privacyUrl: `${config.unlockStaticUrl}/privacy`,
//   termsUrl: `${config.unlockStaticUrl}/terms`,
//   menuSections: [
//     {
//       title: 'About',
//       options: [
//         { label: 'About Unlock', url: `${config.unlockStaticUrl}/about` },
//         {
//           label: 'Roadmap',
//           url: 'https://docs.unlock-protocol.com/governance/roadmap/',
//         },
//         {
//           label: 'Careers',
//           url: 'https://www.notion.so/unlockprotocol/Unlock-Jobs-907811d15c4d490091eb298f71b0954c',
//         },
//       ],
//     },
//     {
//       title: 'Governance',
//       options: [
//         {
//           label: 'Unlock DAO',
//           url: 'https://unlock-protocol.com/blog/unlock-dao',
//         },
//         { label: 'Forum', url: 'https://unlock.community/' },
//         {
//           label: 'Snapshot',
//           url: 'https://snapshot.org/#/unlock-protocol.eth',
//         },
//       ],
//     },
//     {
//       title: 'Community',
//       options: [
//         { label: 'Showcase', url: 'https://showcase.unlock-protocol.com/' },
//         { label: 'Blog', url: `${config.unlockStaticUrl}/blog` },
//         { label: 'Events', url: `${config.unlockStaticUrl}/upcoming-events` },
//         { label: 'Grants', url: `${config.unlockStaticUrl}/grants` },
//       ],
//     },
//     {
//       title: 'Resources',
//       options: [
//         { label: 'Docs', url: 'https://docs.unlock-protocol.com/' },
//         { label: 'Developers', url: `${config.unlockStaticUrl}/developers` },
//         { label: 'Guides', url: `${config.unlockStaticUrl}/blog` },
//         {
//           label: 'Integrations',
//           url: 'https://docs.unlock-protocol.com/move-to-guides/plugins-and-integrations/',
//         },
//         {
//           label: 'Media kit',
//           url: 'https://unlockprotocol.notion.site/Press-Kit-35836bdcc88f400eb5bb429c477c3333',
//         },
//       ],
//     },
//   ],
// }

export const AppLayout = ({
  title,
  description,
  children,
  authRequired = true,
  showLinks = true,
  showHeader = true,
}: DashboardLayoutProps) => {
  const { account } = useAuth()
  const { termsAccepted, saveTermsAccepted, termsLoading } = useTermsOfService()
  const config = useConfig()

  if (termsLoading) {
    return <Loading />
  }

  const showLogin = authRequired && !account

  return (
    <div className="bg-[#090909]">
      <Modal
        isOpen={!termsAccepted}
        setIsOpen={() => {
          saveTermsAccepted()
        }}
      >
        <div className="flex flex-col justify-center gap-4 bg-white">
          <span className="text-base">
            No account required{' '}
            <span role="img" aria-label="stars">
              ✨
            </span>
            , but you need to agree to our{' '}
            <a
              className="outline-none text-brand-ui-primary"
              href={`${config.unlockStaticUrl}/terms`}
            >
              Terms of Service
            </a>{' '}
            and{' '}
            <a
              className="outline-none text-brand-ui-primary"
              href={`${config.unlockStaticUrl}/privacy`}
            >
              Privacy Policy
            </a>
            .
          </span>
          <Button onClick={saveTermsAccepted}>I agree</Button>
        </div>
      </Modal>
      <div className="w-full">
        {showHeader && <AppHeader showLinks={showLinks} />}
        <div className="min-w-full min-h-screen">
          <div className="pt-8">
            <Container>
              <div className="flex flex-col gap-10">
                {(title || description) && (
                  <div className="flex flex-col gap-4">
                    {title && (
                      <h1 className="text-4xl font-bold text-white">{title}</h1>
                    )}
                    {description && (
                      <p className="w-full text-base text-gray-700">
                        {description}
                      </p>
                    )}
                  </div>
                )}
                {showLogin ? (
                  <div className="flex justify-center">
                    <WalletNotConnected />
                  </div>
                ) : (
                  <div>{children}</div>
                )}
              </div>
            </Container>
          </div>
        </div>
        {/* <div className="px-4 mx-auto lg:container">
          <Footer {...FOOTER} />
        </div> */}
      </div>
    </div>
  )
}
