import { Button, Modal } from '@unlock-protocol/ui'
import Link from 'next/link'
import { useAuth } from '~/contexts/AuthenticationContext'
import { addressMinify } from '~/utils/strings'
import { useRouter } from 'next/router'
import { useState } from 'react'
import { AiOutlineMenu as MenuIcon } from 'react-icons/ai'
import { MdExitToApp as DisconnectIcon } from 'react-icons/md'
import { GrClose as MenuCloseIcon } from 'react-icons/gr'
import { Container } from './Container'
import React from 'react'

interface Link {
  label: string
  url: string
}

interface LinksProps {
  mobile?: boolean
}

const links: Link[] = [
  { label: 'Events', url: '/locks' },
  { label: 'Tickets', url: '/keychain' },
  { label: 'Settings', url: '/settings' },
]

interface AppHeaderProps {
  showLinks?: boolean
}

export const AppHeader = ({ showLinks = true }: AppHeaderProps) => {
  const { account, deAuthenticate } = useAuth()
  const [isOpen, setIsOpen] = useState(false)
  const [disconnectModal, setDisconnectModal] = useState(false)
  const router = useRouter()
  const loginUrl = `/login?redirect=${encodeURIComponent(window.location.href)}`

  const Links = ({ mobile = false }: LinksProps) => {
    return (
      <div
        className={`${
          mobile
            ? 'absolute left-0 right-0 block h-auto px-10 pt-20 top-20'
            : ''
        } bg-[#090909]`}
      >
        <ul className="flex flex-col gap-8 md:px-0 md:flex-row">
          {links?.map(({ label, url }, index) => {
            const isActive = router.pathname === url
            return (
              <li
                key={index}
                className={`text-lg ${
                  isActive ? 'text-white' : 'text-white/50'
                }`}
              >
                <Link href={url}>{label}</Link>
              </li>
            )
          })}
        </ul>
      </div>
    )
  }

  const onDisconnect = () => {
    deAuthenticate()
    setDisconnectModal(false)
  }

  return (
    <div className=" pt-3 bg-[#090909]">
      <Modal isOpen={disconnectModal} setIsOpen={setDisconnectModal}>
        <div className="flex flex-col gap-10">
          <div className="flex">
            <img
              src="/images/illustrations/disconnect-wallet.svg"
              className="object-cover w-full h-24"
              alt="disconnect wallet"
            />
          </div>
          <div className="flex flex-col gap-4 mx-auto">
            <span className="text-xl font-bold">
              Are you sure to disconnect?
            </span>
            <div className="flex gap-4">
              <Button onClick={() => setDisconnectModal(false)}>
                Never mind
              </Button>
              <Button variant="outlined-primary" onClick={onDisconnect}>
                Yes, Disconnect
              </Button>
            </div>
          </div>
        </div>
      </Modal>

      <Container>
        <div className="flex justify-between items-center">
          <div className="flex items-center gap-10">
            <div className="flex gap-2">
              <button
                className="flex md:hidden"
                onClick={() => setIsOpen(!isOpen)}
                aria-label="menu-button"
              >
                {isOpen ? <MenuCloseIcon size={20} /> : <MenuIcon size={20} />}
              </button>

              <div className="h-5 md:h-14">
                <img
                  className="h-full"
                  src="/images/svg/moonlab-logo.png"
                  alt="logo"
                />
              </div>
            </div>

            {showLinks && (
              <>
                <div className="hidden md:block">
                  <Links />
                </div>

                <div className="md:hidden">
                  {isOpen && (
                    <div className="">
                      <Links mobile={true} />
                    </div>
                  )}
                </div>
              </>
            )}
          </div>
          <div>
            {account ? (
              <div className="flex gap-2">
                <button onClick={() => setDisconnectModal(true)}>
                  <div className="flex items-center gap-2 border px-6 py-3 rounded-full hover:bg-white/10">
                    <span className="text-white">{addressMinify(account)}</span>
                    <DisconnectIcon className="text-white" size={20} />
                  </div>
                </button>
              </div>
            ) : (
              <Link href={loginUrl}>
                <Button>Connect</Button>
              </Link>
            )}
          </div>
        </div>
      </Container>
    </div>
  )
}
